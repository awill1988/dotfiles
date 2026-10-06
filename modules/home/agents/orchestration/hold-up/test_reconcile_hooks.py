import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import reconcile_hooks as hooks


def definition(command):
    return {"hooks": {"SessionStart": [{"matcher": "", "hooks": [
        {"type": "command", "command": command}
    ]}]}}


class TestReconciliation(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.path = self.root / "settings.json"
        self.old = definition("python3 /home/example/.claude/hooks/vcs_status_hook.py --event SessionStart")
        self.desired = definition("/nix/store/new/bin/hold-up --client claude --event SessionStart")
        self.spec = {"path": str(self.path), "desired": self.desired, "legacy": self.old}

    def read(self):
        return json.loads(self.path.read_text())

    def test_preserves_unrelated_handlers_and_settings(self):
        target = definition("unrelated")
        target["hooks"]["SessionStart"][0]["hooks"].extend(self.old["hooks"]["SessionStart"][0]["hooks"])
        target["model"] = "unchanged"
        target["hooks"]["Stop"] = [{"hooks": [{"type": "command", "command": "other"}]}]
        self.path.write_text(json.dumps(target))
        hooks.reconcile([self.spec])
        result = self.read()
        self.assertEqual(result["model"], "unchanged")
        self.assertEqual(result["hooks"]["Stop"], target["hooks"]["Stop"])
        records = hooks.records(result)
        self.assertIn(hooks.records(definition("unrelated"))[0], records)
        self.assertIn(hooks.records(self.desired)[0], records)
        self.assertNotIn(hooks.records(self.old)[0], records)

    def test_repeated_activation_is_byte_and_mtime_stable(self):
        hooks.reconcile([self.spec])
        previous = self.path.read_bytes(), self.path.stat().st_mtime_ns
        hooks.reconcile([self.spec])
        self.assertEqual(previous, (self.path.read_bytes(), self.path.stat().st_mtime_ns))
        self.assertEqual(len(hooks.records(self.read())), 1)

    def test_upgrade_and_disable_remove_only_owned_handlers(self):
        hooks.reconcile([self.spec])
        upgraded = definition("/nix/store/next/bin/hold-up --client claude --event SessionStart")
        hooks.reconcile([{**self.spec, "desired": upgraded}])
        self.assertEqual(self.read(), upgraded)
        changed = self.read()
        changed["hooks"]["SessionStart"].append({"matcher": "", "hooks": [
            {"type": "command", "command": "custom hold-up invocation"}
        ]})
        self.path.write_text(json.dumps(changed))
        hooks.reconcile([{**self.spec, "desired": {"hooks": {}}}])
        self.assertEqual(len(hooks.records(self.read())), 1)
        self.assertEqual(hooks.records(self.read())[0]["handler"]["command"], "custom hold-up invocation")

    def test_disable_without_manifest_migrates_legacy_only(self):
        self.path.write_text(json.dumps(self.old))
        hooks.reconcile([{**self.spec, "desired": {"hooks": {}}}])
        self.assertEqual(self.read(), {})

    def test_invalid_json_prevents_all_writes(self):
        bad = self.root / "bad.json"
        bad.write_text("{invalid")
        with self.assertRaisesRegex(ValueError, "bad.json"):
            hooks.reconcile([self.spec, {**self.spec, "path": str(bad)}])
        self.assertFalse(self.path.exists())
        self.assertEqual(bad.read_text(), "{invalid")

    def test_invalid_hooks_preserve_file(self):
        self.path.write_text('{"hooks": {"SessionStart": "invalid"}}')
        previous = self.path.read_bytes()
        with self.assertRaisesRegex(ValueError, "settings.json"):
            hooks.reconcile([self.spec])
        self.assertEqual(previous, self.path.read_bytes())

    def test_plugin_conflict_reports_migration_without_mutation(self):
        self.path.write_text('{"enabledPlugins": {"provider-status@awill1988": true}}')
        previous = self.path.read_bytes()
        with self.assertRaisesRegex(ValueError, "disable the provider-status"):
            hooks.reconcile([self.spec])
        self.assertEqual(previous, self.path.read_bytes())

    def test_interrupted_activation_recovers_ownership(self):
        write = hooks.atomic_write
        def fail_after_settings(path, value, **kwargs):
            write(path, value, **kwargs)
            if path == self.path.resolve():
                raise OSError("interrupted")
        with patch.object(hooks, "atomic_write", side_effect=fail_after_settings):
            with self.assertRaises(OSError):
                hooks.reconcile([self.spec])
        hooks.reconcile([{**self.spec, "desired": {"hooks": {}}}])
        self.assertEqual(self.read(), {})

    def test_codex_and_overridden_paths(self):
        codex = self.root / "custom-codex" / "hooks.json"
        desired = definition("/nix/store/test/bin/hold-up --client codex --event SessionStart")
        hooks.reconcile([{"path": str(codex), "desired": desired}])
        self.assertEqual(json.loads(codex.read_text()), desired)
        self.assertEqual(codex.stat().st_mode & 0o777, 0o600)


    def test_manifest_version_and_records_are_validated(self):
        manifest = self.path.with_name(".settings.json.hold-up-managed.json")
        for value in ({"version": 2, "records": []}, {"version": True, "records": []},
                      {"version": 1, "records": [{}]}, {"version": 1, "records": "bad"}):
            manifest.write_text(json.dumps(value))
            with self.assertRaises(ValueError):
                hooks.reconcile([self.spec])
            self.assertFalse(self.path.exists())

    def test_conflicting_resolved_destinations_abort_before_writes(self):
        alias = self.root / "alias"
        alias.symlink_to(self.root, target_is_directory=True)
        conflicting = {**self.spec, "path": str(alias / self.path.name),
                       "desired": definition("different")}
        with self.assertRaisesRegex(ValueError, "conflicting"):
            hooks.reconcile([self.spec, conflicting])
        self.assertFalse(self.path.exists())

    def test_identical_destinations_are_deduplicated(self):
        hooks.reconcile([self.spec, self.spec])
        self.assertEqual(len(hooks.records(self.read())), 1)

    def test_symlink_destination_is_not_replaced(self):
        referent = self.root / "actual.json"
        referent.write_text("{}")
        self.path.symlink_to(referent)
        with self.assertRaisesRegex(ValueError, "symlinked"):
            hooks.reconcile([self.spec])
        self.assertTrue(self.path.is_symlink())
        self.assertEqual(referent.read_text(), "{}")

    def test_concurrent_activation_is_rejected(self):
        with hooks.destination_lock(self.path):
            with self.assertRaisesRegex(ValueError, "another hook activation"):
                hooks.reconcile([self.spec])
        self.assertFalse(self.path.exists())
        hooks.reconcile([self.spec])
        self.assertEqual(self.read(), self.desired)

    def test_user_change_after_preparation_is_preserved(self):
        prepared = hooks.prepare_target(self.spec)
        self.path.write_text('{"model": "user-change"}')
        with self.assertRaisesRegex(ValueError, "destination changed"):
            hooks.apply_prepared([prepared])
        self.assertEqual(self.read(), {"model": "user-change"})

    def test_manifest_change_after_preparation_is_preserved(self):
        prepared = hooks.prepare_target(self.spec)
        manifest = self.path.with_name(".settings.json.hold-up-managed.json")
        manifest.write_text('{"version": 1, "records": []}')
        with self.assertRaisesRegex(ValueError, "destination changed"):
            hooks.apply_prepared([prepared])
        self.assertFalse(self.path.exists())


if __name__ == "__main__":
    unittest.main()
