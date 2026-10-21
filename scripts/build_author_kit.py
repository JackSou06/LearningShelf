#!/usr/bin/env python3
"""Build the portable author kit from protocol sources after validating its example."""
import argparse
import json
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def build(output=None):
    destination = Path(output).resolve() if output else ROOT / 'dist' / 'LearningShelf-AI作者包.zip'
    destination.parent.mkdir(parents=True, exist_ok=True)
    protocol = ROOT / 'protocol'
    node = shutil.which('node')
    if not node:
        raise RuntimeError('Node.js is required to validate the author-kit example')
    validation = subprocess.run([node, str(ROOT / 'scripts/validate-course.cjs'),
                                 str(protocol / 'example-course')], check=True,
                                capture_output=True, text=True)
    result = json.loads(validation.stdout)
    if not result.get('valid'):
        raise RuntimeError('Author-kit example is invalid')
    with tempfile.TemporaryDirectory(prefix='learning-author-kit-') as temporary:
        stage = Path(temporary) / 'LearningShelf-AI作者包'
        stage.mkdir()
        for name in ['AUTHORING.md', 'README.md', 'START_HERE.md', 'TEACHING_CHECKLIST.md', 'APP_PIPELINE.md',
                     'course.schema.json', 'topic.schema.json']:
            shutil.copyfile(protocol / name, stage / name)
        shutil.copyfile(protocol / 'AGENTS.template.md', stage / 'AGENTS.md')
        for name in ['PROMPTS', 'example-course']:
            shutil.copytree(protocol / name, stage / name,
                            ignore=shutil.ignore_patterns('.DS_Store', '__pycache__'))
        (stage / 'VALIDATION.json').write_text(json.dumps({
            'exampleCourseValidation': result,
            'schemaVersion': '1.1',
            'workflow': 'automatic tutorial, teaching review and revision, course conversion',
            'minimumApp': '0.2.3 build16',
            'optionalCapabilities': {'imageDisplay': '0.2.4 build19', 'nativeAuthoringPlan': '0.2.4 build19'},
            'limitations': ['Example format validation does not establish teaching quality or AI answer quality.'],
        }, ensure_ascii=False, indent=2) + '\n')
        files = sorted(p for p in stage.rglob('*') if p.is_file())
        with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
            for file in files:
                if file.is_symlink():
                    raise RuntimeError('Author kit must not contain symlinks')
                archive.write(file, (Path(stage.name) / file.relative_to(stage)).as_posix())
        with zipfile.ZipFile(destination) as archive:
            if archive.testzip() is not None:
                raise RuntimeError('Author-kit CRC verification failed')
            for file in files:
                member = (Path(stage.name) / file.relative_to(stage)).as_posix()
                if archive.read(member) != file.read_bytes():
                    raise RuntimeError('Author-kit roundtrip mismatch: ' + member)
    print(destination)
    return destination


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', help='Destination ZIP (default: dist/LearningShelf-AI作者包.zip)')
    build(parser.parse_args().output)
