#!/usr/bin/env python3
"""Offline AI integration regression suite. Only loopback connections; no account or paid requests."""
from pathlib import Path
import subprocess
import tempfile
from check_library import ROOT, CORE, compile_check

with tempfile.TemporaryDirectory(prefix='learningshelf-ai-checks-') as scratch:
    binary = Path(scratch) / 'ai-checks'
    compile_check('ai_connection_checks', [ROOT / 'native' / (name + '.swift') for name in CORE], binary)
    subprocess.run([str(binary), str(ROOT)], check=True)
