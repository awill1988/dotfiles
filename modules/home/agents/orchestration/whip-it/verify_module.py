"""verify evaluated whip-it module artifacts without activating a user profile."""

import json
from pathlib import Path
import shlex
import sys

cases = json.loads(Path(sys.argv[1]).read_text())
for name, case in cases.items():
    activation = shlex.split(case["activation"])
    specs = json.loads(Path(activation[-1]).read_text())
    paths = {spec["path"]: spec for spec in specs}
    assert len(paths) == len(specs), name

    if not case["enabled"]:
        assert all(not spec["desired"]["hooks"] for spec in specs), name
        continue

    if name == "custom":
        assert case["mode"] == "advisory"
        assert case["defaultMaxSubagents"] == 2
        assert case["autoClamp"] is True

    for path, spec in paths.items():
        hooks = spec["desired"]["hooks"]
        if not hooks:
            continue
        client = (
            "claude"
            if "claude" in path or path.endswith("settings.json")
            else "antigravity"
            if "gemini" in path or "agy" in path
            else "codex"
        )
        assert "PreToolUse" in hooks, f"Missing PreToolUse for {path} ({name})"
        for event, groups in hooks.items():
            assert len(groups) == 1 and len(groups[0]["hooks"]) == 1, f"Invalid group in {path}"
            command = shlex.split(groups[0]["hooks"][0]["command"])
            assert command[0].startswith("/nix/store/") and command[0].endswith("/bin/whip-it"), (
                f"Invalid binary in {command}"
            )
            assert command[1:5] == ["--client", client, "--event", event], (
                f"Invalid args in {command}"
            )

print("whip-it module contracts passed")
