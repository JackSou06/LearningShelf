"""Isolated ZIP fixtures for native course library tests; never touches learner data."""
import json
import shutil
import stat
import sys
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
output = Path(sys.argv[1]).resolve()
output.mkdir(parents=True, exist_ok=True)


def course(name, version):
    folder = output / name
    shutil.copytree(root / 'courses/linear-algebra', folder, dirs_exist_ok=True)
    manifest = json.loads((folder / 'course.json').read_text())
    manifest.update(courseId='library-import-test', title='課程匯入測試', contentVersion=version)
    (folder / 'course.json').write_text(json.dumps(manifest, ensure_ascii=False))
    return folder


def package(folder, name, prefix=''):
    with zipfile.ZipFile(output / name, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(folder.rglob('*')):
            if path.is_file():
                archive.write(path, prefix + path.relative_to(folder).as_posix())


first = course('course-v1', '1.0.0')
second = course('course-v2', '1.0.1')
package(first, 'root.zip')
package(first, 'wrapped.zip', '中文課程/')
package(second, 'updated.zip', 'course/')
invalid = course('invalid-course', '1.0.2')
(invalid / 'topics/vector.md').unlink()
package(invalid, 'invalid.zip')
for name, entries in {
    'traversal.zip': [('../outside.txt', 'escaped')],
    'absolute.zip': [('/tmp/learningshelf-must-not-exist.txt', 'escaped')],
    'windows.zip': [('C:/outside.txt', 'escaped')],
    'duplicate.zip': [('course.json', '{}'), ('COURSE.JSON', '{}')],
    'multiple.zip': [('a/course.json', '{}'), ('b/course.json', '{}')],
}.items():
    with zipfile.ZipFile(output / name, 'w') as archive:
        for path, content in entries:
            archive.writestr(path, content)
with zipfile.ZipFile(output / 'link.zip', 'w') as archive:
    entry = zipfile.ZipInfo('link')
    entry.create_system = 3
    entry.external_attr = (stat.S_IFLNK | 0o777) << 16
    archive.writestr(entry, '/tmp')
    archive.writestr('link/outside.txt', 'escaped')
with zipfile.ZipFile(output / 'oversized.zip', 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=1) as archive:
    with archive.open('large.txt', 'w') as handle:
        for _ in range(201):
            handle.write(b'0' * 1_000_000)
with zipfile.ZipFile(output / 'corrupt.zip', 'w') as archive:
    archive.writestr('course.json', (first / 'course.json').read_bytes())
p = output / 'corrupt.zip'
data = bytearray(p.read_bytes())
# First local entry: fixed header + file name + extra data, then uncompressed content.
start = 30 + int.from_bytes(data[26:28], 'little') + int.from_bytes(data[28:30], 'little')
data[start] ^= 1
p.write_bytes(data)
(output / 'truncated.zip').write_bytes((output / 'root.zip').read_bytes()[:-30])
print(output)
