#!/usr/bin/env python3
"""Native library regression suite; all fixtures and learner records are isolated."""
import argparse
import platform
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE = ['AppStore', 'LibraryOrganization', 'LibraryActions', 'CourseLibrary',
        'CourseLoader', 'RecordStore', 'MarkdownArchiveStore', 'KeyStore', 'HostSession', 'ShareServer',
        'AuthoringMaterials', 'AuthoringVisuals', 'AuthoringValidation', 'CodexAppServer', 'CourseAuthoringStore']


def compile_check(test, sources, binary, ui=False):
    command = ['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
               '-target', platform.machine() + '-apple-macos13.0',
               '-module-cache-path', str(ROOT / '.swift-cache'),
               *map(str, sources), str(ROOT / 'tests' / (test + '.swift')),
               '-I', str(ROOT / 'native/CArchive'), '-larchive',
               '-framework', 'SwiftUI', '-framework', 'JavaScriptCore',
               '-framework', 'Network', '-framework', 'Security', '-framework', 'PDFKit',
               '-lsqlite3', '-o', str(binary)]
    if ui:
        sparkle = ROOT / '.build-tools/Sparkle-2.10.0'
        command += ['-F', str(sparkle), '-framework', 'Sparkle', '-framework', 'WebKit',
                    '-Xlinker', '-rpath', '-Xlinker', str(sparkle)]
    subprocess.run(command, cwd=ROOT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ui', action='store_true', help='Also render and operate an isolated native window')
    parser.add_argument('--ui-only', action='store_true', help='Run only the native window checks')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='learningshelf-library-checks-') as scratch:
        scratch = Path(scratch)
        if not args.ui_only:
            fixtures = scratch / 'fixtures'
            subprocess.run(['python3', str(ROOT / 'tests/create_course_packages.py'), str(fixtures)], check=True)
            for test in ['organization_checks', 'organization_store_checks', 'course_library_checks', 'update_checks']:
                sources = [ROOT / 'native' / (name + '.swift') for name in CORE]
                if test == 'organization_checks': sources = [ROOT / 'native/LibraryOrganization.swift']
                binary = scratch / test
                compile_check(test, sources, binary)
                command = [str(binary), str(ROOT)]
                if test in ['organization_store_checks', 'course_library_checks']: command.append(str(fixtures))
                subprocess.run(command, cwd=ROOT, check=True)
        if args.ui or args.ui_only:
            binary = scratch / 'library-home-ui-checks'
            sources = [p for p in sorted((ROOT / 'native').glob('*.swift')) if p.name != 'LearningShelf.swift']
            compile_check('library_home_ui_checks', sources, binary, ui=True)
            subprocess.run([str(binary), str(ROOT), str(ROOT / 'dist/library-home-review')], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
