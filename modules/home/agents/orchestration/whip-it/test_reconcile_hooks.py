#!/usr/bin/env python3
"""unit tests for whip-it hook reconciliation."""

import json
from pathlib import Path
import shutil
import tempfile
import unittest

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


if __name__ == "__main__":
    unittest.main()
