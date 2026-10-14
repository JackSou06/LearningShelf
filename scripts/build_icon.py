#!/usr/bin/env python3
"""Build a macOS .icns from the preserved LearningShelf PNG artwork."""
import subprocess
import tempfile
from pathlib import Path


def build_icon(source, output):
    source, output = Path(source).resolve(), Path(output).resolve()
    if not source.is_file():
        raise FileNotFoundError(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='learningshelf-icon-') as directory:
        iconset = Path(directory) / 'LearningShelf.iconset'
        iconset.mkdir()
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                suffix = '@2x' if scale == 2 else ''
                target = iconset / f'icon_{size}x{size}{suffix}.png'
                subprocess.run(['sips', '-s', 'format', 'png', '-z', str(size * scale), str(size * scale), str(source), '--out', str(target)], check=True, stdout=subprocess.DEVNULL)
        subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(output)], check=True)
    return output


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    print(build_icon(args.source, args.output))
