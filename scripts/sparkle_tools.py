"""Pinned, checksum-verified official Sparkle distribution (local build cache)."""
import hashlib
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPARKLE_VERSION = '2.10.0'
SPARKLE_SHA256 = 'c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c'
SPARKLE = ROOT / '.build-tools' / ('Sparkle-' + SPARKLE_VERSION)
KEY_ACCOUNT = 'LearningShelf-update-signing'


def ensure_sparkle():
    if (SPARKLE / 'bin/sign_update').is_file():
        return SPARKLE
    SPARKLE.parent.mkdir(parents=True, exist_ok=True)
    archive = SPARKLE.parent / ('Sparkle-' + SPARKLE_VERSION + '.tar.xz')
    subprocess.run(['curl', '-fL', '--retry', '2', '--connect-timeout', '20',
                    'https://github.com/sparkle-project/Sparkle/releases/download/' + SPARKLE_VERSION + '/' + archive.name,
                    '-o', str(archive)], check=True)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SPARKLE_SHA256:
        archive.unlink()
        raise RuntimeError('Sparkle archive checksum mismatch')
    SPARKLE.mkdir(parents=True, exist_ok=True)
    subprocess.run(['tar', '-xJf', str(archive), '-C', str(SPARKLE)], check=True)
    archive.unlink()
    return SPARKLE


if __name__ == '__main__':
    print(ensure_sparkle())
