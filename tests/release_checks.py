"""No network or credentials: assert release integrity gates before publishing the feed."""
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import release_mac as release


class ReleaseChecks(unittest.TestCase):
    def test_all_assets_verified_before_feed(self):
        self.exercise(corrupt=False)

    def test_bad_extra_asset_does_not_publish(self):
        self.exercise(corrupt=True)

    def exercise(self, corrupt):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'updates').mkdir()
            destination = root / 'updates/appcast.xml'
            old = b'<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>16</sparkle:version><sparkle:shortVersionString>0.2.3</sparkle:shortVersionString></item></channel></rss>'
            destination.write_bytes(old)
            feed = root / 'new-feed.xml'
            feed.write_bytes(b'signed-feed-fixture')
            app, kit, sums = [root / name for name in ['App.zip', 'Author.zip', 'SHA256SUMS.txt']]
            for file in [app, kit, sums]:
                file.write_bytes(('fixture-' + file.name).encode())
            assets = {file.name: file for file in [app, kit, sums]}
            events = []
            uploaded = []

            class FakeGitHub:
                def __init__(self, repository):
                    pass

                def request(self, route, method='GET', payload=None, file=None, **kwargs):
                    if method == 'GET':
                        if 'published' in events:
                            return {'id': 1, 'assets': uploaded, 'draft': False}
                        return None
                    if route == '/releases' and method == 'POST':
                        events.append('draft')
                        return {'id': 1, 'assets': [], 'draft': True}
                    if method == 'PATCH':
                        events.append('published')
                        return {}
                    events.append('upload:' + file.name)
                    asset = {'name': file.name, 'size': file.stat().st_size,
                             'digest': 'sha256:' + ('wrong' if corrupt and file == kit else release.digest(file)),
                             'browser_download_url': 'https://example.invalid/' + file.name}
                    uploaded.append(asset.copy())
                    return {**asset, 'browser_download_url': 'https://example.invalid/untagged-draft/' + file.name}

            def fake_run(*args, **kwargs):
                if args[:3] == ('git', 'status', '--porcelain'):
                    return ''
                if args[:4] == ('git', 'remote', 'get-url', 'origin'):
                    return 'https://github.com/JackSou06/LearningShelf.git'
                if args[:3] == ('git', 'rev-parse', 'HEAD'):
                    return 'fixture-source'
                if args[0] == 'curl':
                    self.assertIn('published', events)
                    self.assertNotIn('untagged-draft', args[-3])
                    self.assertEqual(destination.read_bytes(), old)
                    name = args[-3].rsplit('/', 1)[-1]
                    Path(args[-1]).write_bytes(assets[name].read_bytes())
                    events.append('download:' + name)
                if args[:3] == ('git', 'add', 'updates/appcast.xml'):
                    self.assertEqual(destination.read_bytes(), feed.read_bytes())
                    self.assertEqual(len([e for e in events if e.startswith('download:')]), 3)
                    events.append('feed')
                return ''

            with patch.object(release, 'ROOT', root), patch.object(release, 'GitHub', FakeGitHub), patch.object(release, 'run', fake_run):
                config = {'version': '0.3.0', 'build': 22, 'repository': 'JackSou06/LearningShelf'}
                if corrupt:
                    with self.assertRaisesRegex(RuntimeError, 'checksum differs'):
                        release.publish(config, app, feed, 'notes', [kit, sums])
                    self.assertNotIn('published', events)
                    self.assertEqual(destination.read_bytes(), old)
                else:
                    release.publish(config, app, feed, 'notes', [kit, sums])
                    self.assertLess(events.index('upload:SHA256SUMS.txt'), events.index('published'))
                    self.assertLess(events.index('download:SHA256SUMS.txt'), events.index('feed'))


if __name__ == '__main__':
    unittest.main()
