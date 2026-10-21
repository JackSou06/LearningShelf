#!/usr/bin/env python3
"""Prepare a signed update; --publish uploads a Release, then publishes its feed."""
import argparse
import base64
import hashlib
import html
import json
import mimetypes
import os
import plistlib
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path
from build_mac import build
from sparkle_tools import ROOT, KEY_ACCOUNT, ensure_sparkle

SPARKLE_NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE_NS)


def run(*args, **kwargs):
    return subprocess.run(list(map(str, args)), check=True, text=True, capture_output=True, **kwargs).stdout.strip()


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def sign(path):
    signer = ensure_sparkle() / 'bin/sign_update'
    signature = run(signer, '--account', KEY_ACCOUNT, '-p', path)
    verify = [signer, '--account', KEY_ACCOUNT, '--verify', path]
    if Path(path).suffix != '.xml':
        verify.append(signature)
    run(*verify)
    return signature


def write_appcast(path, config, archive, signature, notes, download_url):
    rss = ET.Element('rss', {'version': '2.0'})
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'LearningShelf 更新'
    ET.SubElement(channel, 'link').text = 'https://github.com/' + config['repository']
    ET.SubElement(channel, 'language').text = 'zh-TW'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = 'LearningShelf ' + config['version']
    ET.SubElement(item, 'pubDate').text = format_datetime(datetime.now(timezone.utc), usegmt=True)
    ET.SubElement(item, 'description').text = '<p>' + html.escape(notes).replace('\n', '<br>') + '</p>'
    for name, value in [('version', str(config['build'])), ('shortVersionString', config['version']), ('minimumSystemVersion', '13.0')]:
        ET.SubElement(item, '{' + SPARKLE_NS + '}' + name).text = value
    ET.SubElement(item, 'enclosure', {'url': download_url, 'length': str(archive.stat().st_size),
                                    'type': 'application/octet-stream',
                                    '{' + SPARKLE_NS + '}edSignature': signature})
    ET.indent(rss)
    ET.ElementTree(rss).write(path, encoding='utf-8', xml_declaration=True)


class GitHub:
    """Use an existing GitHub token, keeping credentials out of arguments and files."""
    def __init__(self, repository):
        self.repository = repository
        self.token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
        if not self.token:
            result = run('git', 'credential', 'fill', input='protocol=https\nhost=github.com\n\n',
                         env={**os.environ, 'GIT_TERMINAL_PROMPT': '0', 'GCM_INTERACTIVE': 'never'})
            credentials = dict(line.split('=', 1) for line in result.splitlines() if '=' in line)
            self.token = credentials.get('password')
        if not self.token or any(c in self.token for c in '\r\n"\\'):
            raise RuntimeError('No GitHub token. Sign in with Git or set GH_TOKEN for this command.')

    def request(self, route, method='GET', payload=None, file=None, allow_missing=False):
        url = 'https://api.github.com/repos/' + self.repository + route
        if file:
            url = 'https://uploads.github.com/repos/' + self.repository + route
        with tempfile.TemporaryDirectory(prefix='learning-release-') as temp:
            args = ['curl', '--silent', '--show-error', '--connect-timeout', '20', '--max-time', '900',
                    '--config', '-', '-X', method, '-w', '\n%{http_code}', url]
            headers = ['Authorization: Bearer ' + self.token, 'Accept: application/vnd.github+json',
                       'X-GitHub-Api-Version: 2022-11-28']
            if payload is not None:
                data = Path(temp) / 'request.json'
                data.write_text(json.dumps(payload))
                args += ['--data-binary', '@' + str(data)]
                headers.append('Content-Type: application/json')
            if file:
                args += ['--data-binary', '@' + str(file)]
                headers.append('Content-Type: ' + (mimetypes.guess_type(str(file))[0] or 'application/octet-stream'))
            config = ''.join('header = ' + json.dumps(h) + '\n' for h in headers)
            output = run(*args, input=config)
            body, code = output.rsplit('\n', 1) if '\n' in output else ('', output)
            if code == '404' and allow_missing:
                return None
            data = json.loads(body) if body else {}
            if not 200 <= int(code) < 300:
                raise RuntimeError('GitHub HTTP ' + code + ': ' + data.get('message', 'request failed'))
            return data


def prepare(skip_build=False):
    config = json.loads((ROOT / 'app-version.json').read_text())
    if not isinstance(config['build'], int) or config['build'] <= 0:
        raise ValueError('build must be a positive integer')
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', config['version']):
        raise ValueError('Use a stable numeric version such as 0.1.8')
    sparkle = ensure_sparkle()
    public_key = run(sparkle / 'bin/generate_keys', '--account', KEY_ACCOUNT, '-p')
    if public_key != config['publicEDKey']:
        raise RuntimeError('Keychain signing key differs from app-version.json; do not rotate it accidentally')
    app = ROOT / 'dist/LearningShelf.app' if skip_build else build()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    expected = {'CFBundleIdentifier': 'com.jacksou.LearningShelf', 'CFBundleVersion': str(config['build']),
                'CFBundleShortVersionString': config['version'], 'SUPublicEDKey': public_key,
                'SUFeedURL': config['feedURL'], 'SURequireSignedFeed': True,
                'SUVerifyUpdateBeforeExtraction': True}
    if any(info.get(k) != v for k, v in expected.items()):
        raise RuntimeError('App does not match production configuration; rebuild before publishing')
    run('codesign', '--verify', '--strict', '--deep', app)
    notes = (ROOT / 'updates' / (config['version'] + '.md')).read_text()
    output = ROOT / 'dist/releases' / config['version']
    output.mkdir(parents=True, exist_ok=True)
    archive = output / ('LearningShelf-' + config['version'] + '.zip')
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive)
    signature = sign(archive)
    feed = output / 'appcast.xml'
    download = 'https://github.com/' + config['repository'] + '/releases/download/v' + config['version'] + '/' + archive.name
    write_appcast(feed, config, archive, signature, notes, download)
    sign(feed)  # Do not change the XML after this step; its signature covers the exact bytes.
    print('Prepared:', archive, flush=True)
    print('SHA256:', digest(archive), flush=True)
    return config, archive, feed, notes


def publish(config, archive, feed, notes, extra_assets=()):
    # The app source must already have been committed. The feed is committed only after the asset is live.
    if run('git', 'status', '--porcelain', cwd=ROOT):
        raise RuntimeError('Commit project changes before --publish')
    assets = [archive, *map(Path, extra_assets)]
    if len({path.name for path in assets}) != len(assets) or any(not path.is_file() or path.is_symlink() for path in assets):
        raise RuntimeError('Release assets must be existing regular files with unique names')
    previous_feed = ROOT / 'updates/appcast.xml'
    if previous_feed.exists():
        previous = ET.parse(previous_feed)
        builds = [int(n.text) for n in previous.findall('.//{' + SPARKLE_NS + '}version')]
        versions = [tuple(map(int, n.text.split('.'))) for n in previous.findall('.//{' + SPARKLE_NS + '}shortVersionString')]
        if (builds and config['build'] <= max(builds)) or (versions and tuple(map(int, config['version'].split('.'))) <= max(versions)):
            raise RuntimeError('Increase both version and build above the published feed before releasing')
    origin = run('git', 'remote', 'get-url', 'origin', cwd=ROOT)
    if origin not in ['https://github.com/' + config['repository'] + '.git', 'git@github.com:' + config['repository'] + '.git']:
        raise RuntimeError('origin does not match the release repository')
    source = run('git', 'rev-parse', 'HEAD', cwd=ROOT)
    run('git', 'push', 'origin', 'HEAD:main', cwd=ROOT)
    github = GitHub(config['repository'])
    tag = 'v' + config['version']
    release = github.request('/releases/tags/' + tag, allow_missing=True)
    if release is None:
        release = github.request('/releases', 'POST', {'tag_name': tag, 'target_commitish': source,
                                 'name': 'LearningShelf ' + config['version'], 'body': notes,
                                 'draft': True, 'prerelease': False})
    elif release['target_commitish'] != source:
        raise RuntimeError('This version already belongs to another commit. Increase version/build before publishing.')
    uploaded = {}
    for path in assets:
        asset = next((a for a in release['assets'] if a['name'] == path.name), None)
        if asset is None:
            from urllib.parse import urlencode
            asset = github.request('/releases/' + str(release['id']) + '/assets?' + urlencode({'name': path.name}), 'POST', file=path)
        if asset['size'] != path.stat().st_size or asset.get('digest') != 'sha256:' + digest(path):
            raise RuntimeError('Uploaded asset checksum differs; refusing to publish the update feed: ' + path.name)
        if asset['name'] != path.name:
            raise RuntimeError('GitHub normalized the asset filename; use an ASCII filename: ' + path.name)
        uploaded[path.name] = asset
    if release['draft']:
        github.request('/releases/' + str(release['id']), 'PATCH', {'draft': False, 'make_latest': 'true'})
    # Draft asset URLs may contain an untagged-* placeholder. Publication replaces those URLs.
    release = github.request('/releases/tags/' + tag)
    uploaded = {asset['name']: asset for asset in release['assets']}
    if release['draft'] or any(path.name not in uploaded or uploaded[path.name].get('digest') != 'sha256:' + digest(path) for path in assets):
        raise RuntimeError('Published asset metadata differs; feed has not been published')
    # A successful anonymous download must precede publishing any update metadata.
    with tempfile.TemporaryDirectory(prefix='learning-download-') as temp:
        for path in assets:
            downloaded = Path(temp) / path.name
            # Newly published assets can briefly return 404 before GitHub's edge is ready.
            run('curl', '-fL', '--retry', '5', '--retry-all-errors', '--retry-delay', '3',
                '--connect-timeout', '20', '--max-time', '900',
                uploaded[path.name]['browser_download_url'], '-o', downloaded)
            if digest(downloaded) != digest(path):
                raise RuntimeError('Public download checksum differs; feed has not been published: ' + path.name)
    destination = ROOT / 'updates/appcast.xml'
    destination.write_bytes(feed.read_bytes())
    run('git', 'add', 'updates/appcast.xml', cwd=ROOT)
    if run('git', 'diff', '--cached', '--name-only', cwd=ROOT):
        run('git', 'commit', '-m', 'Publish signed update feed for ' + tag, cwd=ROOT)
    run('git', 'push', 'origin', 'HEAD:main', cwd=ROOT)
    print('Published: https://github.com/' + config['repository'] + '/releases/tag/' + tag)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-build', action='store_true', help='Use the already-built production app')
    parser.add_argument('--publish', action='store_true', help='Upload a GitHub release and commit/push its signed feed')
    parser.add_argument('--asset', action='append', default=[], type=Path, help='Additional release asset; repeat for author kit and checksums')
    args = parser.parse_args()
    result = prepare(args.skip_build)
    if args.publish:
        publish(*result, extra_assets=args.asset)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        # Never print credential-helper output or curl authentication headers.
        if isinstance(error, subprocess.CalledProcessError):
            raise SystemExit('Release command failed. ' + (error.stderr or 'Check build output.'))
        raise SystemExit(str(error))
