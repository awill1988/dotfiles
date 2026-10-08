#!/usr/bin/env python3
"""unit tests for whip-it hook reconciliation."""

import json
import shutil
import tempfile
import unittest
from pathlib import Path

import reconcile_hooks as hooks


def definition(command):
    return {
        "hooks": {
            "PreToolUse": [
                {
                    "matcher": "Agent|Task",
                    "hooks": [{"type": "command", "command": command}],
                }
            ]
        }
    }


class TestReconcileHooks(unittest.TestCase):
    def setUp(self):
        self.temp_dir = Path(tempfile.mkdtemp())
        self.path = self.temp_dir / "settings.json"
        self.desired = definition("/nix/store/test/bin/whip-it --client claude --event PreToolUse")

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def read(self):
        return json.loads(self.path.read_text())

    def test_fresh_install_creates_hooks_and_manifest(self):
        hooks.reconcile([{"path": str(self.path), "desired": self.desired}])
        self.assertEqual(self.read(), self.desired)
        manifest = self.path.with_name(f".{self.path.name}.whip-it-managed.json")
        self.assertTrue(manifest.exists())

    def test_upgrade_replaces_only_managed_handlers(self):
        hooks.reconcile([{"path": str(self.path), "desired": self.desired}])
        upgraded = definition("/nix/store/next/bin/whip-it --client claude --event PreToolUse")
        hooks.reconcile([{"path": str(self.path), "desired": upgraded}])
        self.assertEqual(self.read(), upgraded)

    def test_unrelated_hooks_preserved(self):
        custom = {
            "hooks": {
                "PreToolUse": [
                    {
                        "matcher": "Bash",
                        "hooks": [{"type": "command", "command": "custom check"}],
                    }
                ]
            }
        }
        self.path.write_text(json.dumps(custom))
        hooks.reconcile([{"path": str(self.path), "desired": self.desired}])
        data = self.read()
        self.assertEqual(len(data["hooks"]["PreToolUse"]), 2)

    def test_antigravity_migrates_owned_legacy_handlers(self):
        legacy = definition("old delegation")
        legacy["hooks"]["PreInvocation"] = [
            {"matcher": "", "hooks": [{"type": "command", "command": "old invocation"}]}
        ]
        hooks.reconcile([{"path": str(self.path), "desired": legacy}])
        unrelated = {"enabled": False, "Stop": [{"command": "custom stop"}]}
        target = self.read()
        target["custom"] = unrelated
        self.path.write_text(json.dumps(target))
        desired = {
            "whip-it": {
                "PreToolUse": definition("new delegation")["hooks"]["PreToolUse"],
                "PreInvocation": [{"type": "command", "command": "new invocation"}],
            }
        }
        spec = {"path": str(self.path), "client": "antigravity", "desired": desired}
        hooks.reconcile([spec])
        self.assertEqual(self.read(), {**desired, "custom": unrelated})
        before = self.path.stat().st_mtime_ns
        hooks.reconcile([spec])
        self.assertEqual(self.path.stat().st_mtime_ns, before)
        hooks.reconcile([{**spec, "desired": {"whip-it": {}}}])
        self.assertEqual(self.read(), {"custom": unrelated})

    def test_antigravity_preserves_unowned_handlers_in_same_namespace(self):
        desired = {"whip-it": {"PreInvocation": [{"command": "managed", "type": "command"}]}}
        self.path.write_text(
            json.dumps(
                {
                    "whip-it": {
                        "PreInvocation": [{"command": "custom"}],
                        "enabled": False,
                    }
                }
            )
        )
        spec = {"path": str(self.path), "client": "antigravity", "desired": desired}
        hooks.reconcile([spec])
        hooks.reconcile([{**spec, "desired": {"whip-it": {}}}])
        self.assertEqual(
            self.read(),
            {
                "whip-it": {
                    "PreInvocation": [{"command": "custom"}],
                    "enabled": False,
                }
            },
        )


if __name__ == "__main__":
    unittest.main()
