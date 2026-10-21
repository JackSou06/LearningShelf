#!/usr/bin/env python3
"""Check isolated authoring jobs. Remote Codex is opt-in with --live-source."""
import argparse
import tempfile
from pathlib import Path
from check_library import ROOT, CORE, compile_check
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ui', action='store_true', help='Render the native page in an isolated window')
    parser.add_argument('--pptx', type=Path, help='Also convert a two-slide test PPTX using Keynote/LibreOffice')
    parser.add_argument('--codex', type=Path, help='Installed Codex CLI for optional live checks')
    parser.add_argument('--live-source', type=Path, help='Opt in to real AI generation and isolated auto-import')
    args = parser.parse_args()
    if args.live_source and not args.codex:
        parser.error('--live-source requires --codex and uses that CLI account')
    output = ROOT / 'dist/authoring-review'
    output.mkdir(parents=True, exist_ok=True)
    sources = [ROOT / 'native' / (name + '.swift') for name in CORE]
    fixture = ROOT / 'tests/AuthoringFixture.swift'
    with tempfile.TemporaryDirectory(prefix='learningshelf-authoring-checks-') as scratch:
        scratch = Path(scratch)
        binary = scratch / 'integration'
        compile_check('authoring_checks', [*sources, fixture], binary)
        subprocess.run([str(binary), str(ROOT), str(output)], check=True)
        binary = scratch / 'materials'
        compile_check('authoring_material_checks', sources, binary)
        # Fresh fixture folder permits repeated checks without overwriting an earlier report.
        materials = Path(tempfile.mkdtemp(prefix='materials-', dir=output))
        command = [str(binary), str(materials)]
        if args.pptx:
            command.append(str(args.pptx.resolve()))
        subprocess.run(command, check=True)
        binary = scratch / 'inline-visuals'
        compile_check('inline_visual_checks', [*sources, fixture], binary)
        visuals = Path(tempfile.mkdtemp(prefix='inline-visuals-', dir=output))
        subprocess.run([str(binary), str(ROOT), str(visuals), str(materials / 'fixture.pdf')], check=True)
        binary = scratch / 'optimization'
        compile_check('authoring_optimization_checks', [*sources, fixture], binary)
        optimized = Path(tempfile.mkdtemp(prefix='optimized-', dir=output))
        subprocess.run([str(binary), str(ROOT), str(optimized), str(materials / 'fixture.pdf')], check=True)
        binary = scratch / 'capacity'
        compile_check('course_capacity_checks', sources, binary)
        capacity = Path(tempfile.mkdtemp(prefix='capacity-', dir=output))
        subprocess.run([str(binary), str(ROOT), str(capacity)], check=True)
        if args.ui:
            binary = scratch / 'ui'
            compile_check('authoring_ui_checks', [*sources, fixture, ROOT / 'native/CourseAuthoringView.swift'], binary)
            subprocess.run([str(binary), str(ROOT), str(output / 'ui')], check=True)
        if args.live_source:
            binary = scratch / 'live'
            compile_check('authoring_live_checks', sources, binary)
            live = Path(tempfile.mkdtemp(prefix='live-', dir=output))
            subprocess.run([str(binary), str(ROOT), str(args.codex.resolve()), str(args.live_source.resolve()), str(live)], check=True)


if __name__ == '__main__':
    main()
