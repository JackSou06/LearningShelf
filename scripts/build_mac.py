#!/usr/bin/env python3
"""Build a clean universal macOS app, embedding the pinned Sparkle framework."""
import argparse
import base64
import json
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path
from build_icon import build_icon
from sparkle_tools import ROOT, ensure_sparkle


def build(output=None, test_config=None):
    config = json.loads((ROOT / 'app-version.json').read_text())
    if test_config:
        config.update(json.loads(Path(test_config).read_text()))
        if not output:
            raise ValueError('Test builds require a separate --output directory')
    if len(base64.b64decode(config['publicEDKey'], validate=True)) != 32:
        raise ValueError('Invalid Sparkle public key')
    if not config['feedURL'].startswith('https://') and not test_config:
        raise ValueError('Production updates require HTTPS')
    sparkle = ensure_sparkle()
    destination = Path(output).resolve() if output else ROOT / 'dist'
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='learning-build-', dir=destination) as temporary:
        stage = Path(temporary)
        app = stage / 'LearningShelf.app'
        mac = app / 'Contents/MacOS'
        res = app / 'Contents/Resources'
        frameworks = app / 'Contents/Frameworks'
        mac.mkdir(parents=True)
        res.mkdir()
        frameworks.mkdir()
        for folder, target in [('web', 'Web'), ('courses', 'Courses'), ('protocol', 'Protocol')]:
            shutil.copytree(ROOT / folder, res / target, ignore=shutil.ignore_patterns('.DS_Store', '__pycache__'))
        (res / 'Web/library.js').write_text('window.BUNDLED_COURSES=[];\n')
        build_icon(ROOT / 'resources/learningShelf_icon_macos.png', res / 'LearningShelf.icns')
        # Preserve framework symlinks and helper executable permissions.
        shutil.copytree(sparkle / 'Sparkle.framework', frameworks / 'Sparkle.framework', symlinks=True)
        shutil.copy2(sparkle / 'LICENSE', res / 'Sparkle-LICENSE.txt')
        binaries = []
        for arch in ['arm64', 'x86_64']:
            binary = stage / ('LearningShelf-' + arch)
            subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-O',
                            '-target', f'{arch}-apple-macos13.0', '-module-cache-path', str(ROOT / '.swift-cache'),
                            *map(str, sorted((ROOT / 'native').glob('*.swift'))),
                            '-I', str(ROOT / 'native/CArchive'), '-larchive',
                            '-F', str(sparkle), '-framework', 'Sparkle',
                            '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks',
                            '-framework', 'SwiftUI', '-framework', 'WebKit', '-framework', 'JavaScriptCore',
                            '-framework', 'Security', '-framework', 'Network', '-framework', 'PDFKit',
                            '-lsqlite3', '-o', str(binary)], check=True)
            binaries.append(str(binary))
        subprocess.run(['lipo', '-create', *binaries, '-output', str(mac / 'LearningShelf')], check=True)
        info = {
            'CFBundleName': '學習工具', 'CFBundleDisplayName': '學習工具',
            'CFBundleIdentifier': 'com.jacksou.LearningShelf' + ('.update-test' if test_config else ''),
            'CFBundleExecutable': 'LearningShelf', 'CFBundlePackageType': 'APPL',
            'CFBundleShortVersionString': config['version'], 'CFBundleVersion': str(config['build']),
            'CFBundleIconFile': 'LearningShelf', 'LSMinimumSystemVersion': '13.0',
            'NSHighResolutionCapable': True,
            'NSAppleEventsUsageDescription': '將你選擇的 PowerPoint 教材透過 Keynote 轉為逐頁圖片，供 AI 製作課程。',
            'NSLocalNetworkUsageDescription': '分享選定課程，讓同一網路的裝置閱讀。',
            'SUFeedURL': config['feedURL'], 'SUPublicEDKey': config['publicEDKey'],
            'SUEnableAutomaticChecks': False, 'SUAutomaticallyUpdate': False,
            'SUAllowsAutomaticUpdates': False, 'SUEnableSystemProfiling': False,
            'SUVerifyUpdateBeforeExtraction': True,
            'SURequireSignedFeed': True, 'SUSignedFeedFailureExpirationInterval': 0,
        }
        if test_config:
            info['NSAppTransportSecurity'] = {'NSAllowsLocalNetworking': True}
            info['LearningShelfTestDataDirectory'] = config['testDataDirectory']
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        # No Hardened Runtime / library validation: this distribution has no Developer ID.
        subprocess.run(['codesign', '--force', '--sign', '-', '--deep', str(app)], check=True)
        subprocess.run(['codesign', '--verify', '--strict', '--deep', str(app)], check=True)
        target = destination / 'LearningShelf.app'
        if target.exists():
            shutil.rmtree(target)
        app.rename(target)
    print(target)
    return target


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', help='Output directory (default: dist)')
    parser.add_argument('--test-config', help='JSON overrides, isolated test bundle identifier; never publish this build')
    args = parser.parse_args()
    build(args.output, args.test_config)
