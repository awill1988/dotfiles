#!/usr/bin/env python3
"""reconcile only recorded hook handlers, preserving all unrelated client settings."""

import argparse
import copy
from contextlib import ExitStack, contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile


def read_object(path):
    if path.is_symlink():
        raise ValueError(f"symlinked hook file must be migrated explicitly: {path}")
    if not path.exists():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(value, dict):
            raise ValueError("expected an object")
        return value
    except (ValueError, OSError) as error:
        raise ValueError(f"invalid json at {path}: {error}") from error


UNSPECIFIED = object()


def snapshot(path):
    if path.is_symlink():
        raise ValueError(f"symlinked hook file must be migrated explicitly: {path}")
    try:
        info = path.stat()
        return (info.st_dev, info.st_ino, info.st_mtime_ns, info.st_ctime_ns,
                hashlib.sha256(path.read_bytes()).digest())
    except FileNotFoundError:
        return None


def assert_unchanged(path, expected):
    if expected is not UNSPECIFIED and snapshot(path) != expected:
        raise ValueError(f"destination changed during activation; retry after reviewing: {path}")


def atomic_write(path, value, expected=UNSPECIFIED):
    assert_unchanged(path, expected)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix=f".{path.name}.", delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(value, stream, indent=2)
            stream.write("\n")
        assert_unchanged(path, expected)
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def records(document):
    hooks = document.get("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError("hooks must be an object")
    result = []
    for event, groups in hooks.items():
        if not isinstance(groups, list):
            raise ValueError(f"hooks.{event} must be an array")
        for group in groups:
            if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
                raise ValueError(f"invalid matcher group in hooks.{event}")
            for handler in group["hooks"]:
                if not isinstance(handler, dict):
                    raise ValueError(f"invalid handler in hooks.{event}")
                result.append({"event": event, "group": {k: v for k, v in group.items() if k != "hooks"},
                               "handler": handler})
    return result


def merge_hooks(target, desired, owned):
    result = copy.deepcopy(target)
    hooks = result.get("hooks", {})
    for event, groups in list(hooks.items()):
        kept_groups = []
        for group in groups:
            metadata = {key: value for key, value in group.items() if key != "hooks"}
            kept = [handler for handler in group["hooks"]
                    if {"event": event, "group": metadata, "handler": handler} not in owned]
            if kept or not group["hooks"]:
                kept_groups.append({**metadata, "hooks": kept})
        if kept_groups:
            hooks[event] = kept_groups
        else:
            del hooks[event]
    for event, groups in desired.get("hooks", {}).items():
        hooks.setdefault(event, []).extend(copy.deepcopy(groups))
    if hooks:
        result["hooks"] = hooks
    else:
        result.pop("hooks", None)
    return result


def prepare_target(spec):
    path = Path(spec["path"])
    manifest_path = path.with_name(f".{path.name}.hold-up-managed.json")
    target_snapshot = snapshot(path)
    manifest_snapshot = snapshot(manifest_path)
    target = read_object(path)
    desired = spec["desired"]
    previous = read_object(manifest_path)
    try:
        records(target)
        current_records = records(desired)
        previous_records = previous.get("records", [])
        if manifest_snapshot is not None and (type(previous.get("version")) is not int or previous["version"] != 1):
            raise ValueError("unsupported ownership manifest version")
        if not isinstance(previous_records, list) or any(
            not isinstance(record, dict) or set(record) != {"event", "group", "handler"}
            or not isinstance(record["event"], str) or not isinstance(record["group"], dict)
            or "hooks" in record["group"] or not isinstance(record["handler"], dict)
            or not isinstance(record["handler"].get("command"), str)
            or record["handler"].get("type") != "command"
            for record in previous_records
        ):
            raise ValueError("invalid ownership manifest")
        if current_records and any(enabled is True and name.startswith("provider-status@")
                                   for name, enabled in target.get("enabledPlugins", {}).items()):
            raise ValueError("disable the provider-status Claude plugin before enabling direct hold-up hooks")
        owned = previous_records + current_records + records(spec.get("legacy", {}))
        merged = merge_hooks(target, desired, owned)
    except (ValueError, AttributeError, TypeError) as error:
        raise ValueError(f"cannot reconcile {path}: {error}") from error
    assert_unchanged(path, target_snapshot)
    assert_unchanged(manifest_path, manifest_snapshot)
    return path, manifest_path, target, merged, previous_records, current_records, target_snapshot, manifest_snapshot


@contextmanager
def destination_lock(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_name(f".{path.name}.hold-up.lock")
    descriptor = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError(f"another hook activation owns {path}") from error
        yield
    finally:
        os.close(descriptor)


def reconcile(specs):
    normalized = {}
    for spec in specs:
        path = Path(spec["path"])
        if not path.is_absolute():
            raise ValueError(f"hook destination must be absolute: {path}")
        path = path.parent.resolve() / path.name
        value = {**spec, "path": str(path)}
        if path in normalized and normalized[path] != value:
            raise ValueError(f"conflicting hook specifications for {path}")
        normalized[path] = value
    for spec in normalized.values():
        prepare_target(spec)
    with ExitStack() as locks:
        for path in sorted(normalized):
            locks.enter_context(destination_lock(path))
        prepared = [prepare_target(spec) for spec in normalized.values()]
        apply_prepared(prepared)


def apply_prepared(prepared):
    for path, manifest_path, target, merged, previous, desired, target_snapshot, manifest_snapshot in prepared:
        if target == merged and not desired and not manifest_path.exists():
            continue
        # Record both generations first so an interrupted activation can recover.
        pending = {"version": 1, "records": previous + desired}
        final = {"version": 1, "records": desired}
        if target != merged:
            assert_unchanged(path, target_snapshot)
            atomic_write(manifest_path, pending, expected=manifest_snapshot)
            manifest_snapshot = snapshot(manifest_path)
            atomic_write(path, merged, expected=target_snapshot)
            target_snapshot = snapshot(path)
        if read_object(manifest_path) != final:
            assert_unchanged(path, target_snapshot)
            atomic_write(manifest_path, final, expected=manifest_snapshot)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("specification", type=Path)
    args = parser.parse_args()
    try:
        specs = json.loads(args.specification.read_text(encoding="utf-8"))
        reconcile(specs)
    except (ValueError, OSError, TypeError, KeyError) as error:
        sys.stderr.write(f"error: hold-up hook activation: {error}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
