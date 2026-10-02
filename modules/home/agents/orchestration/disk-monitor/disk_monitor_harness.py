#!/usr/bin/env python3
"""Offline Metal-compatible disk space monitoring harness.

Periodically evaluates disk usage metrics and executes an offline,
Apple Silicon Metal-accelerated local model (via llama-cli with -ngl 99)
whenever available storage decreases by more than the configured threshold
(default 1.0 percentage points).
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

DEFAULT_STATE_PATH = Path.home() / ".cache" / "disk_monitor" / "state.json"
DEFAULT_MODEL_PATH = Path.home() / ".local" / "share" / "models" / "qwen2.5-coder-7b.gguf"
DEFAULT_MOUNT_POINT = "/"
DEFAULT_THRESHOLD_PCT = 1.0
DEFAULT_CHECK_INTERVAL_SECONDS = 1800  # 30 minutes
DEFAULT_GPU_LAYERS = 99


def log(msg: str) -> None:
    """Print lowercase log message to stderr."""
    sys.stderr.write(f"[disk-monitor] {msg.lower()}\n")
    sys.stderr.flush()


def get_disk_metrics(mount_point: str = DEFAULT_MOUNT_POINT) -> dict[str, float]:
    """Retrieve total, used, and free disk metrics in gigabytes and percentage."""
    usage = shutil.disk_usage(mount_point)
    if usage.total <= 0:
        raise ValueError(f"invalid total disk capacity on mount '{mount_point}'")

    total_gb = usage.total / (1024**3)
    free_gb = usage.free / (1024**3)
    used_gb = usage.used / (1024**3)
    free_pct = (usage.free / usage.total) * 100.0
    used_pct = (usage.used / usage.total) * 100.0

    return {
        "timestamp": time.time(),
        "total_gb": round(total_gb, 2),
        "used_gb": round(used_gb, 2),
        "free_gb": round(free_gb, 2),
        "free_pct": round(free_pct, 4),
        "used_pct": round(used_pct, 4),
    }


def load_state(state_path: Path) -> dict[str, Any] | None:
    """Load prior disk monitoring state from disk, handling missing or corrupt files."""
    if not state_path.exists():
        return None
    try:
        with open(state_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, dict) and "free_pct" in data:
                return data
            log("state file invalid structure; reinitializing")
            return None
    except (json.JSONDecodeError, OSError) as exc:
        log(f"unable to read state file: {exc}; reinitializing")
        return None


def save_state(state_path: Path, metrics: dict[str, Any]) -> None:
    """Atomically persist disk metrics to prevent race conditions or partial writes."""
    state_path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = state_path.with_suffix(".tmp")
    with open(temp_path, "w", encoding="utf-8") as f:
        json.dump(metrics, f, indent=2)
    temp_path.replace(state_path)


def format_concise_prompt(
    mount_point: str,
    current: dict[str, Any],
    delta: float,
    prior: dict[str, Any],
) -> str:
    """Construct concise instruction prompt for the offline model."""
    return (
        f"You are a system monitoring harness agent. Available disk storage on mount '{mount_point}' "
        f"has decreased by {delta:.2f} percentage points.\n"
        f"Current Free: {current['free_gb']} GB ({current['free_pct']:.2f}% of {current['total_gb']} GB total)\n"
        f"Prior Baseline: {prior['free_gb']} GB ({prior['free_pct']:.2f}%)\n"
        f"Delta: -{delta:.2f}%\n\n"
        "Output a concise 3-line alert summary stating the remaining storage, the delta, and the alert status."
    )


def dispatch_local_notification(title: str, message: str) -> None:
    """Send local notification banner on macOS using osascript."""
    if sys.platform != "darwin":
        return
    script = f'display notification "{message}" with title "{title}"'
    try:
        subprocess.run(["osascript", "-e", script], check=False, capture_output=True)
    except Exception as exc:
        log(f"notification dispatch failed: {exc}")


def invoke_offline_metal_model(
    prompt: str,
    model_path: Path,
    gpu_layers: int = DEFAULT_GPU_LAYERS,
) -> str:
    """Execute offline inference using llama-cli with Apple Silicon Metal GPU offload."""
    if not model_path.exists():
        log(f"local model checkpoint not found at '{model_path}'; emitting structured alert")
        return (
            f"[Disk Space Alert - Offline Model]\n"
            f"- Status: Active threshold breach\n"
            f"- Details: {prompt.splitlines()[1] if len(prompt.splitlines()) > 1 else prompt}"
        )

    log(f"invoking offline metal model via llama-cli (gpu_layers: {gpu_layers})")
    cmd = [
        "llama-cli",
        "-m",
        str(model_path),
        "-ngl",
        str(gpu_layers),
        "-c",
        "2048",
        "--temp",
        "0.1",
        "-p",
        f"System: You are an offline system agent.\nUser: {prompt}\nAssistant:",
        "--no-warmup",
        "--simple-io",
    ]

    env = os.environ.copy()
    env.update(
        {
            "DO_NOT_TRACK": "1",
            "DISABLE_TELEMETRY": "1",
            "NO_PROXY": "*",
            "LLAMA_LOG_LEVEL": "error",
        }
    )

    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            env=env,
            check=False,
            timeout=120,
        )
        if proc.returncode != 0:
            log(f"llama-cli failed with exit {proc.returncode}: {proc.stderr.strip()[:200]}")
            return f"[Disk Space Alert] Offline inference error: {proc.stderr.strip()[:100]}"
        return proc.stdout.strip()
    except Exception as exc:
        log(f"offline model execution failed: {exc}")
        return f"[Disk Space Alert] Inference exception: {exc}"


def invoke_agent_workflow(
    prompt: str,
    runner: str = "llama_metal",
    model_path: Path = DEFAULT_MODEL_PATH,
    gpu_layers: int = DEFAULT_GPU_LAYERS,
) -> str:
    """Execute background agent session via chosen runner."""
    log(f"invoking background agent runner: {runner}")

    if runner == "dry_run":
        log(f"dry-run prompt:\n{prompt}")
        return f"[dry-run alert] {prompt.splitlines()[0]}"

    if runner == "llama_metal":
        return invoke_offline_metal_model(prompt, model_path=model_path, gpu_layers=gpu_layers)

    if runner == "local_server":
        # Loopback connection to offline local server (e.g., llama-server or opencode)
        import urllib.request
        payload = json.dumps(
            {
                "model": "local",
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.1,
            }
        ).encode("utf-8")
        req = urllib.request.Request(
            "http://127.0.0.1:8080/v1/chat/completions",
            data=payload,
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                return data["choices"][0]["message"]["content"]
        except Exception as exc:
            log(f"local server request failed: {exc}")
            return f"[Disk Space Alert] Local server connection failed: {exc}"

    raise ValueError(f"unsupported runner: {runner}")


def evaluate_and_step(
    mount_point: str,
    state_path: Path,
    threshold_pct: float,
    runner: str,
    model_path: Path = DEFAULT_MODEL_PATH,
    gpu_layers: int = DEFAULT_GPU_LAYERS,
    simulated_current: dict[str, float] | None = None,
) -> bool:
    """Perform a single evaluation step. Returns True if an alert workflow was triggered."""
    current = simulated_current if simulated_current is not None else get_disk_metrics(mount_point)
    prior = load_state(state_path)

    if prior is None:
        log(f"initializing baseline: {current['free_pct']:.2f}% free on '{mount_point}'")
        save_state(state_path, current)
        return False

    delta = prior["free_pct"] - current["free_pct"]

    if delta >= threshold_pct:
        log(
            f"disk decrease of {delta:.2f}% exceeded threshold of {threshold_pct:.2f}% "
            f"({prior['free_pct']:.2f}% -> {current['free_pct']:.2f}%)"
        )
        prompt = format_concise_prompt(mount_point, current, delta, prior)
        report = invoke_agent_workflow(
            prompt,
            runner=runner,
            model_path=model_path,
            gpu_layers=gpu_layers,
        )

        sys.stdout.write(f"\n{report}\n")
        sys.stdout.flush()

        dispatch_local_notification(
            title="Disk Space Alert",
            message=f"Free storage dropped by {delta:.2f}%. Remaining: {current['free_gb']} GB ({current['free_pct']:.1f}%).",
        )

        # Reset baseline to current level following alert
        save_state(state_path, current)
        return True

    if current["free_pct"] > prior["free_pct"]:
        log(
            f"disk space freed ({prior['free_pct']:.2f}% -> {current['free_pct']:.2f}%); "
            "updating baseline upward"
        )
        save_state(state_path, current)
    else:
        log(
            f"delta {delta:.2f}% below threshold {threshold_pct:.2f}%; no alert triggered"
        )

    return False


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Run 30-minute offline Metal disk space evaluation harness."
    )
    parser.add_argument(
        "--mount",
        default=os.environ.get("DISK_MOUNT_POINT", DEFAULT_MOUNT_POINT),
        help=f"Mount point to inspect (default: {DEFAULT_MOUNT_POINT})",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=float(os.environ.get("THRESHOLD_PERCENT", DEFAULT_THRESHOLD_PCT)),
        help=f"Drop threshold in percentage points (default: {DEFAULT_THRESHOLD_PCT})",
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=int(os.environ.get("CHECK_INTERVAL_SECONDS", DEFAULT_CHECK_INTERVAL_SECONDS)),
        help=f"Polling interval in seconds for daemon mode (default: {DEFAULT_CHECK_INTERVAL_SECONDS})",
    )
    parser.add_argument(
        "--state-file",
        type=Path,
        default=Path(os.environ.get("DISK_STATE_PATH", str(DEFAULT_STATE_PATH))),
        help=f"Path to JSON state file (default: {DEFAULT_STATE_PATH})",
    )
    parser.add_argument(
        "--model-path",
        type=Path,
        default=Path(os.environ.get("LOCAL_MODEL_PATH", str(DEFAULT_MODEL_PATH))),
        help=f"Path to offline GGUF model file (default: {DEFAULT_MODEL_PATH})",
    )
    parser.add_argument(
        "--gpu-layers",
        type=int,
        default=int(os.environ.get("GPU_LAYERS", DEFAULT_GPU_LAYERS)),
        help=f"Number of layers to offload to Metal GPU (default: {DEFAULT_GPU_LAYERS})",
    )
    parser.add_argument(
        "--runner",
        choices=["llama_metal", "local_server", "dry_run"],
        default=os.environ.get("AGENT_RUNNER", "llama_metal"),
        help="Agent invocation runner mechanism (default: llama_metal)",
    )
    parser.add_argument(
        "--daemon",
        action="store_true",
        help="Run continuously in background polling loop rather than single check",
    )
    parser.add_argument(
        "--print-metrics",
        action="store_true",
        help="Print current disk metrics and exit",
    )
    return parser.parse_args()


def main() -> int:
    """Entry point for offline disk monitoring harness."""
    args = parse_args()

    if args.print_metrics:
        metrics = get_disk_metrics(args.mount)
        sys.stdout.write(json.dumps(metrics, indent=2) + "\n")
        return 0

    if not args.daemon:
        evaluate_and_step(
            mount_point=args.mount,
            state_path=args.state_file,
            threshold_pct=args.threshold,
            runner=args.runner,
            model_path=args.model_path,
            gpu_layers=args.gpu_layers,
        )
        return 0

    log(f"starting daemon mode on mount '{args.mount}' every {args.interval}s")
    while True:
        try:
            evaluate_and_step(
                mount_point=args.mount,
                state_path=args.state_file,
                threshold_pct=args.threshold,
                runner=args.runner,
                model_path=args.model_path,
                gpu_layers=args.gpu_layers,
            )
        except Exception as exc:
            log(f"error during evaluation tick: {exc}")
        time.sleep(args.interval)


if __name__ == "__main__":
    sys.exit(main())
