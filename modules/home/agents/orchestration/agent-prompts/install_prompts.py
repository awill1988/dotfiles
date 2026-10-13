#!/usr/bin/env python3
"""Install one verified source into resolved instruction destinations."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile


def validate(manifest):
    source = Path(manifest['source'])
    content = source.read_bytes()
    if not content.strip() or '\x00' in content.decode('utf-8'):
        raise ValueError('instructions must be nonempty utf-8 text')
    files = [Path(path) for path in manifest['files']]
    aliases = {Path(path): Path(target) for path, target in manifest['aliases'].items()}
    backup_dir = Path(manifest['backup_dir'])
    destinations = files + list(aliases)
    if len(set(destinations)) != len(destinations):
        raise ValueError('conflicting instruction destinations')
    if any(target not in files for target in aliases.values()):
        raise ValueError('alias must target a canonical instruction file')
    for path in destinations + [backup_dir]:
        if not path.is_absolute() or '..' in path.parts:
            raise ValueError(f'destination must be absolute and normalized: {path}')
        for parent in path.parents:
            if parent.exists() and not parent.is_dir():
                raise ValueError(f'parent is not a directory: {parent}')
            if parent.is_symlink() and not parent.exists():
                raise ValueError(f'parent is a dangling symlink: {parent}')
    resolved = [path.parent.resolve() / path.name for path in destinations]
    if len(set(resolved)) != len(resolved):
        raise ValueError('instruction destinations overlap through directory aliases')
    if any(parent in resolved for path in resolved for parent in path.parents):
        raise ValueError('instruction destination is also a parent directory')
    for path in destinations:
        if path.is_symlink():
            if path.exists() and not path.is_file():
                raise ValueError(f'instruction symlink targets a non-file: {path}')
        elif path.exists() and not stat.S_ISREG(path.stat().st_mode):
            raise ValueError(f'instruction destination is not a regular file: {path}')
    if backup_dir.exists() and not backup_dir.is_dir():
        raise ValueError('backup destination is not a directory')
    return content, files, aliases, backup_dir


def backup(path, directory):
    if not path.is_file():
        return
    content = path.read_bytes()
    identity = hashlib.sha256(os.fsencode(str(path))).hexdigest()
    digest = hashlib.sha256(content).hexdigest()
    destination = directory / identity / (digest + '.md')
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not destination.exists():
        with destination.open('xb') as stream:
            os.chmod(destination, 0o600)
            stream.write(content)
        (destination.parent / 'path.txt').write_text(str(path) + '\n')


def atomic_file(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())
    try:
        temporary.chmod(0o600)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def install(manifest, dry_run=False):
    content, files, aliases, backup_dir = validate(manifest)
    changes = []
    for path in files:
        if (path.is_symlink() or not path.is_file() or path.read_bytes() != content
                or stat.S_IMODE(path.stat().st_mode) != 0o600):
            changes.append((path, None))
    for path, target in aliases.items():
        if not path.is_symlink() or os.readlink(path) != str(target):
            changes.append((path, target))
    if dry_run:
        return [str(path) for path, _ in changes]
    # Preserve displaced content before changing any instruction destination.
    for path, _ in changes:
        backup(path, backup_dir)
    for path, target in changes:
        if target is None:
            atomic_file(path, content)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            descriptor, name = tempfile.mkstemp(dir=path.parent)
            os.close(descriptor)
            temporary = Path(name)
            try:
                temporary.unlink()
                temporary.symlink_to(target)
                os.replace(temporary, path)
            finally:
                temporary.unlink(missing_ok=True)
    return [str(path) for path, _ in changes]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    changes = install(json.loads(args.manifest.read_text()), args.dry_run)
    print(f'instruction destinations updated: {len(changes)}')


if __name__ == '__main__':
    main()
