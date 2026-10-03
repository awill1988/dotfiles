#!/usr/bin/env python3
"""Unit tests for offline Metal disk space monitor harness."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from disk_monitor_harness import (
    dispatch_local_notification,
    evaluate_and_step,
    format_concise_prompt,
    get_disk_metrics,
    invoke_offline_metal_model,
    load_state,
    save_state,
)


class TestOfflineMetalDiskMonitorHarness(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.state_path = Path(self.temp_dir.name) / "test_state.json"
        self.model_path = Path(self.temp_dir.name) / "dummy_model.gguf"

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_get_disk_metrics(self) -> None:
        metrics = get_disk_metrics("/")
        self.assertIn("free_pct", metrics)
        self.assertIn("total_gb", metrics)
        self.assertIn("free_gb", metrics)
        self.assertGreater(metrics["total_gb"], 0)
        self.assertGreaterEqual(metrics["free_pct"], 0.0)
        self.assertLessEqual(metrics["free_pct"], 100.0)

    def test_save_and_load_state(self) -> None:
        data = {"free_pct": 45.5, "free_gb": 100.0, "total_gb": 500.0}
        save_state(self.state_path, data)
        loaded = load_state(self.state_path)
        self.assertIsNotNone(loaded)
        self.assertEqual(loaded["free_pct"], 45.5)

    def test_initial_run_sets_baseline(self) -> None:
        initial = {
            "total_gb": 500.0,
            "used_gb": 250.0,
            "free_gb": 250.0,
            "free_pct": 50.0,
            "used_pct": 50.0,
        }
        triggered = evaluate_and_step(
            mount_point="/",
            state_path=self.state_path,
            threshold_pct=1.0,
            runner="dry_run",
            simulated_current=initial,
        )
        self.assertFalse(triggered)
        saved = load_state(self.state_path)
        self.assertIsNotNone(saved)
        self.assertEqual(saved["free_pct"], 50.0)

    def test_sub_threshold_drop_does_not_alert(self) -> None:
        initial = {
            "total_gb": 500.0,
            "used_gb": 250.0,
            "free_gb": 250.0,
            "free_pct": 50.0,
            "used_pct": 50.0,
        }
        save_state(self.state_path, initial)

        # 0.8% drop (50.0% -> 49.2%)
        second = {
            "total_gb": 500.0,
            "used_gb": 254.0,
            "free_gb": 246.0,
            "free_pct": 49.2,
            "used_pct": 50.8,
        }
        triggered = evaluate_and_step(
            mount_point="/",
            state_path=self.state_path,
            threshold_pct=1.0,
            runner="dry_run",
            simulated_current=second,
        )
        self.assertFalse(triggered)

    @patch("disk_monitor_harness.invoke_agent_workflow")
    @patch("disk_monitor_harness.dispatch_local_notification")
    def test_threshold_breach_triggers_metal_workflow(
        self,
        mock_notify: MagicMock,
        mock_invoke: MagicMock,
    ) -> None:
        mock_invoke.return_value = "[Disk Space Alert] Drop confirmed"

        # Baseline at 50.0%
        initial = {
            "total_gb": 500.0,
            "used_gb": 250.0,
            "free_gb": 250.0,
            "free_pct": 50.0,
            "used_pct": 50.0,
        }
        save_state(self.state_path, initial)

        # 1.5% drop (50.0% -> 48.5%)
        second = {
            "total_gb": 500.0,
            "used_gb": 257.5,
            "free_gb": 242.5,
            "free_pct": 48.5,
            "used_pct": 51.5,
        }
        triggered = evaluate_and_step(
            mount_point="/",
            state_path=self.state_path,
            threshold_pct=1.0,
            runner="llama_metal",
            model_path=self.model_path,
            gpu_layers=99,
            simulated_current=second,
        )
        self.assertTrue(triggered)
        mock_invoke.assert_called_once()
        mock_notify.assert_called_once()

        # State updated to current level
        saved = load_state(self.state_path)
        self.assertEqual(saved["free_pct"], 48.5)

    def test_missing_model_fallback(self) -> None:
        missing_path = Path("/nonexistent/model.gguf")
        output = invoke_offline_metal_model("Storage alert test", model_path=missing_path)
        self.assertIn("[Disk Space Alert - Offline Model]", output)

    @patch("subprocess.run")
    def test_llama_cli_metal_flags(self, mock_subproc: MagicMock) -> None:
        self.model_path.touch()
        mock_subproc.return_value = MagicMock(returncode=0, stdout="Alert generated")

        result = invoke_offline_metal_model(
            "Check storage",
            model_path=self.model_path,
            gpu_layers=99,
        )
        self.assertEqual(result, "Alert generated")
        mock_subproc.assert_called_once()

        cmd = mock_subproc.call_args[0][0]
        self.assertEqual(cmd[0], "llama-cli")
        self.assertIn("-ngl", cmd)
        self.assertIn("99", cmd)
        self.assertIn("-m", cmd)
        self.assertIn(str(self.model_path), cmd)

        # Check offline environment variables
        env = mock_subproc.call_args[1]["env"]
        self.assertEqual(env["DO_NOT_TRACK"], "1")
        self.assertEqual(env["DISABLE_TELEMETRY"], "1")
        self.assertEqual(env["NO_PROXY"], "*")

    def test_format_concise_prompt(self) -> None:
        current = {"free_gb": 80.0, "free_pct": 40.0, "total_gb": 200.0}
        prior = {"free_gb": 85.0, "free_pct": 42.5, "total_gb": 200.0}
        prompt = format_concise_prompt("/", current, 2.5, prior)
        self.assertIn("decreased by 2.50 percentage points", prompt)
        self.assertIn("Current Free: 80.0 GB", prompt)
        self.assertIn("Prior Baseline: 85.0 GB", prompt)

    @patch("sys.platform", "darwin")
    @patch("subprocess.run")
    def test_dispatch_local_notification_banner_and_modal(
        self, mock_subproc: MagicMock
    ) -> None:
        mock_subproc.return_value = MagicMock(returncode=0, stdout="button returned:OK", stderr="")

        dispatch_local_notification(
            title="Disk Alert",
            message="Storage dropped 1.5%",
            modal=True,
            timeout_seconds=30,
        )

        self.assertEqual(mock_subproc.call_count, 2)

        # Call 1: Notification banner with sound
        banner_call = mock_subproc.call_args_list[0][0][0]
        self.assertEqual(banner_call[0], "osascript")
        self.assertIn('display notification "Storage dropped 1.5%" with title "Disk Alert" sound name "default"', banner_call[2])

        # Call 2: Critical modal alert with timeout
        alert_call = mock_subproc.call_args_list[1][0][0]
        self.assertEqual(alert_call[0], "osascript")
        self.assertIn('display alert "Disk Alert" message "Storage dropped 1.5%" as critical giving up after 30', alert_call[2])

    @patch("sys.platform", "darwin")
    @patch("subprocess.run")
    def test_dispatch_local_notification_no_modal(
        self, mock_subproc: MagicMock
    ) -> None:
        mock_subproc.return_value = MagicMock(returncode=0, stdout="", stderr="")

        dispatch_local_notification(
            title="Disk Alert",
            message="Storage dropped 1.5%",
            modal=False,
        )

        self.assertEqual(mock_subproc.call_count, 1)
        banner_call = mock_subproc.call_args_list[0][0][0]
        self.assertEqual(banner_call[0], "osascript")
        self.assertIn('display notification "Storage dropped 1.5%" with title "Disk Alert" sound name "default"', banner_call[2])

    @patch("sys.platform", "linux")
    @patch("subprocess.run")
    def test_dispatch_local_notification_non_darwin(
        self, mock_subproc: MagicMock
    ) -> None:
        dispatch_local_notification(
            title="Disk Alert",
            message="Storage dropped 1.5%",
            modal=True,
        )
        mock_subproc.assert_not_called()


if __name__ == "__main__":
    unittest.main()
