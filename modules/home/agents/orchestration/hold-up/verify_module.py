"""verify evaluated module artifacts without activating a user profile."""

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
        assert not case["files"], name
        assert all(not spec["desired"]["hooks"] for spec in specs), name
        continue
    assert ".claude/hooks/vcs_status_hook.py" in case["files"], name
    feeds = json.loads(Path(case["feeds"]).read_text())
    if name in ("custom", "legacy_custom"):
        assert feeds["feeds"] == [], name
    if name == "custom":
        assert feeds["cache_ttl_seconds"] == 42
    if name != "no_profiles":
        assert "/home/example/custom-client/hooks.json" in paths, name
        assert paths["/home/example/.config/profiles/work/codex/hooks.json"]["desired"]["hooks"] == {}, name
        assert paths["/home/example/.config/profiles/restricted/codex/hooks.json"]["desired"]["hooks"] == {}, name
    for path, spec in paths.items():
        hooks = spec["desired"]["hooks"]
        if name == "no_codex" and path.endswith("/hooks.json"):
            assert hooks == {}, name
        if not hooks:
            continue
        client = "codex" if path.endswith("/hooks.json") else "claude"
        tool_event = "PostToolUse" if client == "codex" else "PostToolUseFailure"
        assert set(hooks) == {"SessionStart", "UserPromptSubmit", "PreToolUse", tool_event}, name
        for event, groups in hooks.items():
            assert len(groups) == 1 and len(groups[0]["hooks"]) == 1, name
            command = shlex.split(groups[0]["hooks"][0]["command"])
            assert command[0].startswith("/nix/store/") and command[0].endswith("/bin/hold-up"), name
            assert command[1:5] == ["--client", client, "--event", event], name
            assert "--profile" in command, name
            assert Path(command[0]).is_file(), name
print("hold-up module contracts passed")
