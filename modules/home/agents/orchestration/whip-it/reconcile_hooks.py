#!/usr/bin/env python3
"""reconcile only recorded whip-it hook handlers, preserving all unrelated client settings."""

import argparse
import copy
import fcntl
import hashlib
import json
import os
import sys
import tempfile
from contextlib import ExitStack, contextmanager
from pathlib import Path


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
        return (
            info.st_dev,
            info.st_ino,
            info.st_mtime_ns,
            info.st_ctime_ns,
            hashlib.sha256(path.read_bytes()).digest(),
        )
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
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            delete=False,
        ) as stream:
            temporary = Path(stream.name)
            json.dump(value, stream, indent=2)
            stream.write("\n")
        assert_unchanged(path, expected)
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def records(document, named=False):
    if named:
        result = []
        for name, events in document.items():
            if not isinstance(events, dict):
                raise ValueError("named hook must be an object")
            event_lists = {key: value for key, value in events.items() if key != "enabled"}
            result.extend({**record, "name": name} for record in records({"hooks": event_lists}))
        return result
    hooks = document.get("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError("hooks must be an object")
    result = []
    for event, groups in hooks.items():
        if not isinstance(groups, list):
            raise ValueError(f"hooks.{event} must be an array")
        for group in groups:
            if isinstance(group, dict) and "command" in group:
                result.append({"event": event, "group": None, "handler": group})
                continue
            if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
                raise ValueError(f"invalid matcher group in hooks.{event}")
            for handler in group["hooks"]:
                if not isinstance(handler, dict):
                    raise ValueError(f"invalid handler in hooks.{event}")
                result.append(
                    {
                        "event": event,
                        "group": {k: v for k, v in group.items() if k != "hooks"},
                        "handler": handler,
                    }
                )
    return result


def merge_hooks(target, desired, owned, named=False):
    if named:
        result = copy.deepcopy(target)
        for name in set(target) | set(desired):
            current = target.get(name, {})
            wanted = desired.get(name, {})
            scoped = [
                {key: value for key, value in record.items() if key != "name"}
                for record in owned
                if record.get("name", "hooks") == name
            ]
            merged = merge_hooks(
                {"hooks": {k: v for k, v in current.items() if k != "enabled"}},
                {"hooks": {k: v for k, v in wanted.items() if k != "enabled"}},
                scoped,
            ).get("hooks", {})
            if "enabled" in current:
                merged["enabled"] = current["enabled"]
            if "enabled" in wanted:
                merged["enabled"] = wanted["enabled"]
            if merged:
                result[name] = merged
            else:
                result.pop(name, None)
        return result
    result = copy.deepcopy(target)
    hooks = result.get("hooks", {})
    for event, groups in list(hooks.items()):
        kept_groups = []
        for group in groups:
            if "command" in group:
                if {"event": event, "group": None, "handler": group} not in owned:
                    kept_groups.append(group)
                continue
            metadata = {key: value for key, value in group.items() if key != "hooks"}
            kept = [
                handler
                for handler in group["hooks"]
                if {"event": event, "group": metadata, "handler": handler} not in owned
            ]
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
    manifest_path = path.with_name(f".{path.name}.whip-it-managed.json")
    target_snapshot = snapshot(path)
    manifest_snapshot = snapshot(manifest_path)
    target = read_object(path)
    desired = spec["desired"]
    previous = read_object(manifest_path)
    named = spec.get("client") == "antigravity"
    try:
        records(target, named)
        current_records = records(desired, named)
        previous_records = previous.get("records", [])
        if manifest_snapshot is not None and (
            type(previous.get("version")) is not int or previous["version"] not in (1, 2)
        ):
            raise ValueError("unsupported ownership manifest version")
        if not isinstance(previous_records, list) or any(
            not isinstance(record, dict)
            or set(record)
            not in ({"event", "group", "handler"}, {"event", "group", "handler", "name"})
            or ("name" in record and (not named or not isinstance(record["name"], str)))
            or not isinstance(record["event"], str)
            or (record["group"] is not None and not isinstance(record["group"], dict))
            or (isinstance(record["group"], dict) and "hooks" in record["group"])
            or not isinstance(record["handler"], dict)
            or not isinstance(record["handler"].get("command"), str)
            or record["handler"].get("type") != "command"
            for record in previous_records
        ):
            raise ValueError("invalid ownership manifest")
        owned = previous_records + current_records + records(spec.get("legacy", {}), named)
        merged = merge_hooks(target, desired, owned, named)
    except (ValueError, AttributeError, TypeError) as error:
        raise ValueError(f"cannot reconcile {path}: {error}") from error
    assert_unchanged(path, target_snapshot)
    assert_unchanged(manifest_path, manifest_snapshot)
    return (
        path,
        manifest_path,
        target,
        merged,
        previous_records,
        current_records,
        target_snapshot,
        manifest_snapshot,
    )


@contextmanager
def destination_lock(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_name(f".{path.name}.whip-it.lock")
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
        path = str(Path(spec["path"]))
        if path in normalized:
            raise ValueError(f"duplicate target path in specification: {path}")
        normalized[path] = spec
    ordered = sorted(normalized.values(), key=lambda item: item["path"])
    with ExitStack() as stack:
        for spec in ordered:
            stack.enter_context(destination_lock(Path(spec["path"])))
        prepared = [prepare_target(spec) for spec in ordered]
        for (
            path,
            manifest_path,
            target,
            merged,
            previous_records,
            current_records,
            target_snapshot,
            manifest_snapshot,
        ) in prepared:
            if target == merged and previous_records == current_records:
                continue
            atomic_write(path, merged, target_snapshot)
            atomic_write(
                manifest_path,
                {
                    "version": 2 if any("name" in r for r in current_records) else 1,
                    "records": current_records,
                },
                manifest_snapshot,
            )


def main():
    parser = argparse.ArgumentParser(description="reconcile whip-it agent lifecycle hooks")
    parser.add_argument("spec", type=Path, help="path to hook specification json")
    args = parser.parse_args()
    try:
        reconcile(json.loads(args.spec.read_text(encoding="utf-8")))
    except Exception as error:
        sys.stderr.write(f"error: whip-it hook activation: {error}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
