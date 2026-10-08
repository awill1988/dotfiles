"""verify evaluated whip-it module artifacts without activating a user profile."""

import json
import shlex
import sys
from pathlib import Path

cases = json.loads(Path(sys.argv[1]).read_text())
for name, case in cases.items():
    activation = shlex.split(case["activation"])
    specs = json.loads(Path(activation[-1]).read_text())
    paths = {spec["path"]: spec for spec in specs}
    assert len(paths) == len(specs), name

    if not case["enabled"]:
        assert all(not any(spec["desired"].values()) for spec in specs), name
        continue

    if name == "custom":
        assert case["mode"] == "advisory"
        assert case["defaultMaxSubagents"] == 2
        assert case["autoClamp"] is True

    for path, spec in paths.items():
        client = spec["client"]
        hooks = spec["desired"]["whip-it" if client == "antigravity" else "hooks"]
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
            assert len(groups) == 1, f"Invalid group in {path}"
            if client == "antigravity" and event == "PreInvocation":
                assert "hooks" not in groups[0] and "matcher" not in groups[0]
                handler = groups[0]
            else:
                assert len(groups[0]["hooks"]) == 1, f"Invalid group in {path}"
                handler = groups[0]["hooks"][0]
            command = shlex.split(handler["command"])
            assert command[0].startswith("/nix/store/") and command[0].endswith("/bin/whip-it"), (
                f"Invalid binary in {command}"
            )
            assert command[1:5] == ["--client", client, "--event", event], (
                f"Invalid args in {command}"
            )

print("whip-it module contracts passed")
