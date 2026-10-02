#!/usr/bin/env python3
"""Continuous Agent Loop Orchestrator with Profile-Aware Model Switching.

Executes autonomous development loops across Claude, Codex, and AGY.
Enforces profile boundaries (e.g. work vs personal), zero data collection,
and worktree isolation via worktrunk (wt).
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path


RATE_LIMIT_PATTERNS = [
    r"rate[\s_-]?limit",
    r"usage[\s_-]?limit",
    r"exceeded\s+your\s+current\s+quota",
    r"429\s+too\s+many\s+requests",
    r"overloaded",
    r"capacity\s+exceeded",
    r"token[\s_-]?limit",
]


def log(msg: str) -> None:
    """Print lowercase log message."""
    sys.stderr.write(f"[agent-loop] {msg.lower()}\n")
    sys.stderr.flush()


def run_cmd(
    cmd: list[str], cwd: Path | None = None, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    """Run command returning CompletedProcess."""
    full_env = os.environ.copy()
    # Enforce zero data collection and telemetry shutdown
    full_env.update(
        {
            "DO_NOT_TRACK": "1",
            "DISABLE_TELEMETRY": "1",
            "CODEX_DISABLE_TELEMETRY": "1",
            "AGY_TELEMETRY_ENABLED": "false",
            "ANTIGRAVITY_TELEMETRY_ENABLED": "false",
            "OPENCODE_TELEMETRY_ENABLED": "false",
            "OTEL_SDK_DISABLED": "true",
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
            "DISABLE_NON_ESSENTIAL_MODEL_CALLS": "1",
            "DISABLE_AUTOUPDATER": "1",
            "DISABLE_GROWTHBOOK": "1",
            "DISABLE_ERROR_REPORTING": "1",
        }
    )
    if env:
        full_env.update(env)

    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        env=full_env,
        capture_output=True,
        text=True,
    )


def resolve_profile(target_dir: Path) -> tuple[str, list[str]]:
    """Query profile-router for active profile and permitted models."""
    profile_proc = run_cmd(["profile-router", "--show-profile"], cwd=target_dir)
    profile = (
        profile_proc.stdout.strip()
        if profile_proc.returncode == 0 and profile_proc.stdout.strip()
        else None
    )

    if not profile:
        target_str = str(target_dir.resolve())
        home = str(Path.home())
        target_norm = target_str.replace(home, "~")
        if target_norm.startswith("~/projects/arro"):
            profile = "work"
        elif target_norm.startswith("~/projects/yourmood"):
            profile = "yourmoodai"
        else:
            profile = os.environ.get("DEVELOPER_PROFILE", "personal")

    models_proc = run_cmd(["profile-router", "--show-allowed-models"], cwd=target_dir)
    if models_proc.returncode == 0 and models_proc.stdout.strip():
        allowed_models = [
            m.strip() for m in models_proc.stdout.strip().split(",") if m.strip()
        ]
    else:
        allowed_models = (
            ["claude-secondary"] if profile == "work" else ["claude", "codex", "agy"]
        )

    return profile, allowed_models



def is_rate_limited(output: str) -> bool:
    """Check text for rate-limit indicators."""
    lower = output.lower()
    return any(re.search(pat, lower) for pat in RATE_LIMIT_PATTERNS)


def slugify(text: str) -> str:
    """Create clean branch slug from prompt."""
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", text.strip().lower())
    slug = slug.strip("-")[:40]
    return slug or "task"


def setup_worktree(target_dir: Path, slug: str) -> Path:
    """Create isolated worktree via worktrunk (wt switch -c)."""
    branch_name = f"agent-loop/{slug}"
    log(f"creating worktree for branch {branch_name}")

    proc = run_cmd(["wt", "switch", "-c", branch_name], cwd=target_dir)
    if proc.returncode != 0:
        log(f"wt switch failed: {proc.stderr.strip()}; falling back to git worktree")
        wt_dir = target_dir.parent / f"{target_dir.name}.agent-loop-{slug}"
        git_proc = run_cmd(
            ["git", "worktree", "add", "-b", branch_name, str(wt_dir)], cwd=target_dir
        )
        if git_proc.returncode != 0:
            log(
                f"git worktree add failed: {git_proc.stderr.strip()}; running in-place"
            )
            return target_dir
        return wt_dir

    # Detect current directory after wt switch
    pwd_proc = run_cmd(["pwd", "-P"])
    if pwd_proc.returncode == 0 and pwd_proc.stdout.strip():
        return Path(pwd_proc.stdout.strip())
    return target_dir


def build_turn_prompt(
    objective: str,
    iteration: int,
    max_iterations: int,
    model_name: str,
    last_error: str | None,
) -> str:
    """Format prompt for the active model iteration."""
    prompt = [
        f"Goal: {objective}",
        f"Iteration: {iteration} of {max_iterations} (Active Agent: {model_name})",
        "",
        "Instructions:",
        "- Work iteratively towards completing the Goal.",
        "- Review existing project code and adhere to repository architecture and guidelines in AGENTS.md.",
        "- Do not attribute work or commits to any AI system (no co-authored-by or agent tags).",
        "- Record notable implementation steps or remaining issues in .agent-loop/progress.md.",
    ]

    if last_error:
        prompt.extend(
            [
                "",
                "Previous Verification / Test Failure:",
                "```",
                last_error[-4000:],  # Bound length
                "```",
                "Fix the discrepancies identified above.",
            ]
        )

    return "\n".join(prompt)


def invoke_model(
    model: str,
    prompt: str,
    cwd: Path,
    profile: str,
    timeout: int,
) -> tuple[int, str, str]:
    """Execute model CLI non-interactively."""
    log(f"invoking {model} (profile: {profile}) in {cwd}")

    extra_env = {}
    if model == "claude-secondary":
        extra_env["CLAUDE_CONFIG_DIR"] = os.path.expanduser("~/.config/claude-secondary")
        cmd = ["claude", "-p", prompt, "--dangerously-skip-permissions"]
    elif model == "claude":
        cmd = ["claude", "-p", prompt, "--dangerously-skip-permissions"]
    elif model == "codex":
        cmd = ["codex", "exec", prompt, "--dangerously-bypass-approvals-and-sandbox"]
    elif model in ("agy", "gemini"):
        cmd = ["agy", "-p", prompt, "--dangerously-skip-permissions"]
    else:
        raise ValueError(f"unsupported model: {model}")

    try:
        full_env = os.environ.copy()
        full_env.update(
            {
                "DO_NOT_TRACK": "1",
                "DISABLE_TELEMETRY": "1",
                "CODEX_DISABLE_TELEMETRY": "1",
                "AGY_TELEMETRY_ENABLED": "false",
                "ANTIGRAVITY_TELEMETRY_ENABLED": "false",
                "OPENCODE_TELEMETRY_ENABLED": "false",
                "OTEL_SDK_DISABLED": "true",
                "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
                "DISABLE_NON_ESSENTIAL_MODEL_CALLS": "1",
            }
        )
        full_env.update(extra_env)

        proc = subprocess.run(
            cmd,
            cwd=str(cwd),
            env=full_env,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired:
        return 124, "", f"execution timed out after {timeout} seconds"
    except Exception as exc:
        return 1, "", str(exc)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Continuous agent loop orchestrator with profile switching and worktree isolation."
    )
    parser.add_argument("prompt", help="Task objective or instruction")
    parser.add_argument(
        "--order",
        help="Comma-separated model sequence (e.g. claude,codex,agy or claude-secondary)",
    )
    parser.add_argument(
        "--profile",
        help="Explicit developer profile override (defaults to path-prefix resolution)",
    )
    parser.add_argument(
        "--max-iterations",
        type=int,
        default=20,
        help="Maximum loop iterations (default: 20)",
    )
    parser.add_argument(
        "--verify",
        help="Verification command to execute after each turn (e.g. 'nix flake check')",
    )
    parser.add_argument(
        "--no-worktree",
        action="store_true",
        help="Do not create an isolated Git worktree; run directly in current directory",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate profile resolution and model sequence without running turns",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=600,
        help="Turn timeout in seconds (default: 600)",
    )
    parser.add_argument(
        "--no-auto-commit",
        action="store_true",
        help="Do not commit changes automatically when verification passes",
    )

    args = parser.parse_args()

    origin_dir = Path.cwd().resolve()
    resolved_profile, allowed_models = resolve_profile(origin_dir)
    active_profile = args.profile or resolved_profile

    log(f"resolved developer profile: {active_profile}")
    log(f"profile allowed models: {', '.join(allowed_models)}")

    # Model sequence validation
    if args.order:
        requested_order = [m.strip() for m in args.order.split(",") if m.strip()]
        for m in requested_order:
            if m not in allowed_models:
                sys.stderr.write(
                    f"error: model '{m}' is not permitted in profile '{active_profile}' (allowed: {allowed_models})\n"
                )
                return 2
        model_sequence = requested_order
    else:
        model_sequence = allowed_models

    log(f"active model execution sequence: {', '.join(model_sequence)}")

    if args.dry_run:
        log("dry run: profile and model sequence verified successfully")
        return 0

    # Worktree initialization
    if not args.no_worktree:
        git_check = run_cmd(["git", "rev-parse", "--is-inside-work-tree"], cwd=origin_dir)
        if git_check.returncode == 0 and git_check.stdout.strip() == "true":
            task_slug = slugify(args.prompt)
            working_dir = setup_worktree(origin_dir, task_slug)
        else:
            log("not inside a git repository; running in-place")
            working_dir = origin_dir
    else:
        working_dir = origin_dir

    log(f"working directory: {working_dir}")

    # Initialize state directory
    state_dir = working_dir / ".agent-loop"
    state_dir.mkdir(parents=True, exist_ok=True)
    (state_dir / "objective.md").write_text(args.prompt + "\n")

    progress_file = state_dir / "progress.md"
    if not progress_file.exists():
        progress_file.write_text(f"# Progress Log: {args.prompt}\n\nProfile: {active_profile}\n\n")

    state = {
        "objective": args.prompt,
        "profile": active_profile,
        "allowed_models": allowed_models,
        "sequence": model_sequence,
        "iteration": 0,
        "max_iterations": args.max_iterations,
        "completed": False,
        "history": [],
    }

    last_error: str | None = None
    model_idx = 0
    iteration = 1

    while iteration <= args.max_iterations:
        state["iteration"] = iteration
        current_model = model_sequence[model_idx % len(model_sequence)]
        log(f"starting iteration {iteration}/{args.max_iterations} using {current_model}")

        turn_prompt = build_turn_prompt(
            objective=args.prompt,
            iteration=iteration,
            max_iterations=args.max_iterations,
            model_name=current_model,
            last_error=last_error,
        )

        retcode, stdout, stderr = invoke_model(
            model=current_model,
            prompt=turn_prompt,
            cwd=working_dir,
            profile=active_profile,
            timeout=args.timeout,
        )

        combined_output = f"{stdout}\n{stderr}".strip()

        # Check for rate limiting
        if is_rate_limited(combined_output):
            log(f"model {current_model} rate-limited or quota exceeded")
            state["history"].append(
                {
                    "iteration": iteration,
                    "model": current_model,
                    "status": "rate_limited",
                    "error": combined_output[:500],
                }
            )

            if len(model_sequence) > 1:
                log("swapping to next available model in sequence")
                model_idx += 1
                continue
            else:
                log(f"single model '{current_model}' throttled in restricted profile '{active_profile}'; pausing")
                time.sleep(30)
                iteration += 1
                continue

        state["history"].append(
            {
                "iteration": iteration,
                "model": current_model,
                "status": "success" if retcode == 0 else "failed",
                "retcode": retcode,
            }
        )

        # Verification Gate
        if args.verify:
            log(f"executing verification: {args.verify}")
            verify_proc = run_cmd(["sh", "-c", args.verify], cwd=working_dir)
            if verify_proc.returncode == 0:
                log("verification passed successfully")
                state["completed"] = True
                (state_dir / "state.json").write_text(json.dumps(state, indent=2) + "\n")

                if not args.no_auto_commit:
                    run_cmd(["git", "add", "-A"], cwd=working_dir)
                    commit_slug = slugify(args.prompt)
                    commit_proc = run_cmd(
                        ["git", "commit", "-m", f"feat: {commit_slug}"], cwd=working_dir
                    )
                    if commit_proc.returncode == 0:
                        log(f"committed changes: feat: {commit_slug}")

                log("task complete")
                return 0
            else:
                log("verification failed")
                last_error = f"{verify_proc.stdout}\n{verify_proc.stderr}".strip()
                with progress_file.open("a") as f:
                    f.write(
                        f"### Iteration {iteration} Verification Failure\n```\n{last_error}\n```\n\n"
                    )
        else:
            # If no verify command provided, single turn completes unless non-zero
            if retcode == 0:
                log("turn completed successfully with no verification command specified")
                state["completed"] = True
                (state_dir / "state.json").write_text(json.dumps(state, indent=2) + "\n")
                return 0

        (state_dir / "state.json").write_text(json.dumps(state, indent=2) + "\n")
        iteration += 1

    log("max iterations reached without verification passing")
    return 1


if __name__ == "__main__":
    sys.exit(main())
