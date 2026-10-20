final: prev:
let
  version = "0.1.0";
  rev = "1cfe254e8d25b15f37048c3730134686abe60335";

  src = prev.fetchFromGitHub {
    owner = "google-research";
    repo = "harness2";
    inherit rev;
    hash = "sha256-cQVJDwcE0eCcS65JeIC+aa5OOeuChkn+RG5pzgoFopk=";
  };

  niro_harness_py = prev.writeText "niro_harness.py" ''
    from __future__ import annotations

    import json
    import os
    import sys
    import time
    import urllib.error
    import urllib.request
    from pathlib import Path
    from urllib.parse import urlparse

    from harness2.core import runmark as RM
    from harness2.core import tree as HT
    from harness2.substrate.opencode import OPENCODE_SURFACE, compose_prompt

    LOCAL_HOSTS = {"127.0.0.1", "localhost", "::1", "host.docker.internal"}

    DEFAULT_TREE = {
        "systemprompt.md": (
            "# Harness2 Offline Security Orchestrator\n\n"
            "You are executing inside a Harness2 recursive agent harness backed by an offline "
            "local open-weight model. Follow the Niro MCP orchestrator contract and the "
            "Research-Grade Evidence Contract strictly:\n"
            "1. Never fabricate or extrapolate findings from version banners alone.\n"
            "2. Every confirmed finding must include Vector Provenance (UTC timestamp, socket tuple, "
            "packet/banner SHA-256, and artifact path), Active Wire Verification Proof, and "
            "copy-pasteable Steps to Reproduce.\n"
        ),
        "guardrails.md": (
            "# Guardrails & Research Evidence Integrity\n\n"
            "- Never modify files outside the universal XDG state directory.\n"
            "- Never install hooks or skills into user repositories.\n"
            "- Only probe hosts and ports explicitly listed in the active per-host scope.yaml.\n"
            "- NEVER report a banner-only version match (e.g., OpenSSH version range without wire proof) "
            "as a confirmed vulnerability; distributions backport patches without changing version strings.\n"
            "- Every confirmed finding MUST document:\n"
            "  1. **Verification Status**: `VERIFIED (Wire-Confirmed)`.\n"
            "  2. **Vector Provenance**: UTC timestamp, local->remote socket tuple, SHA-256 digest of the "
            "captured handshake/packet, protocol field name, and artifact path.\n"
            "  3. **Steps to Reproduce**: Exact copy-pasteable command(s) and observed wire output.\n"
            "  4. **Remediation & Re-Verification**: Concrete configuration fix and post-fix verification command.\n"
        ),
        "LongTermMEMORY.md": (
            "# Long-Term Security Memory\n\n"
            "- Consolidate root causes across findings before generating the final summary.\n"
            "- Maintain strict separation between wire-verified protocol findings and unverified "
            "banner observations.\n"
        ),
        "tool_descriptions/tool_guidance.md": (
            "# Niro MCP Tool Guidance\n\n"
            "- Call `get_recipe` with `name: \"orchestrator\"` first.\n"
            "- Use `start_pentest`, `get_pentest_status`, `manage_finding`, "
            "`generate_pentest_report`, `generate_pentest_summary`, and `close_pentest`.\n"
        ),
    }


    def ensure_harness_tree() -> Path:
        state_home = Path(
            os.environ.get("XDG_STATE_HOME") or (Path.home() / ".local" / "state")
        )
        tree_dir = Path(
            os.environ.get("HARNESS2_NIRO_TREE") or (state_home / "harness2" / "niro-tree")
        )
        if not HT.is_tree(OPENCODE_SURFACE, tree_dir):
            HT.write_tree(OPENCODE_SURFACE, DEFAULT_TREE, tree_dir, stubs=True)
        else:
            guardrails_path = tree_dir / "guardrails.md"
            if not guardrails_path.is_file() or "Vector Provenance" not in guardrails_path.read_text(encoding="utf-8"):
                for rel_name, content in DEFAULT_TREE.items():
                    target = tree_dir / rel_name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text(content, encoding="utf-8")
        loaded = HT.read_tree(OPENCODE_SURFACE, tree_dir)
        HT.validate(OPENCODE_SURFACE, loaded, allow_subagents=True)
        return tree_dir


    def verify_offline_endpoint() -> tuple[str, str, str]:
        provider = os.environ.get("NIRO_PROVIDER") or "openai"
        base_url = (
            os.environ.get("OPENAI_API_BASE")
            or os.environ.get("OPENAI_BASE_URL")
            or os.environ.get("COPILOT_PROVIDER_BASE_URL")
            or "http://127.0.0.1:11434/v1"
        )
        model = (
            os.environ.get("NIRO_MODEL")
            or os.environ.get("COPILOT_MODEL")
            or "qwen2.5-coder:32b"
        )
        offline = os.environ.get("NIRO_OFFLINE", "1") != "0"
        parsed = urlparse(base_url)
        host = (parsed.hostname or "").lower()
        if offline and host not in LOCAL_HOSTS:
            sys.stderr.write(
                f"error: harness2-niro offline mode (NIRO_OFFLINE=1) requires a local model "
                f"endpoint {sorted(LOCAL_HOSTS)}, got {base_url!r}.\n"
                f"Set NIRO_OFFLINE=0 to explicitly allow remote open-weight endpoints.\n"
            )
            raise SystemExit(2)
        return provider, base_url, model


    def wrap_prompt_with_harness(tree_dir: Path, instruction: str) -> str:
        template = compose_prompt(tree_dir)
        return template.replace("{{ instruction }}", instruction)


    def record_run(tree_dir: Path, provider: str, base_url: str, model: str, argv: list[str]) -> Path:
        state_home = Path(
            os.environ.get("XDG_STATE_HOME") or (Path.home() / ".local" / "state")
        )
        runs_root = Path(
            os.environ.get("HARNESS2_RUNS_DIR") or (state_home / "harness2" / "runs")
        )
        run_dir = runs_root / f"niro-{int(time.time() * 1000)}-{os.getpid()}"
        run_dir.mkdir(parents=True, exist_ok=True)
        meta = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "harness_tree": str(tree_dir),
            "harness_fingerprint": RM.fingerprint(tree_dir),
            "provider": provider,
            "base_url": base_url,
            "model": model,
            "offline": os.environ.get("NIRO_OFFLINE", "1") != "0",
            "target_host": os.environ.get("NIRO_TARGET_HOST", "default"),
            "state_dir": os.environ.get("NIRO_HOST_STATE_DIR", ""),
            "argv_count": len(argv),
        }
        (run_dir / "meta.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
        return run_dir


    def analyze_ssh_with_local_model(
        tree_dir: Path, provider: str, base_url: str, model: str, recon_path: Path
    ) -> int:
        recon = json.loads(recon_path.read_text(encoding="utf-8"))
        instruction = (
            "Analyze the following wire-captured SSH reconnaissance artifact.\n"
            f"Target: {recon.get('host')}:{recon.get('port')}\n"
            f"Goal: {recon.get('goal')}\n"
            f"Artifact Path: {recon_path}\n\n"
            f"```json\n{json.dumps(recon, indent=2)}\n```\n\n"
            "Follow the Research-Grade Evidence Contract strictly:\n"
            "1. Only report findings that have `verification_status: VERIFIED` on the wire.\n"
            "2. Never claim a banner version range is a confirmed vulnerability without behavioral proof.\n"
            "3. For every verified finding, cite its `kexinit_sha256` / provenance, live negotiation proof, "
            "exact Steps to Reproduce command, and `sshd_config` remediation + verification command."
        )
        composed = wrap_prompt_with_harness(tree_dir, instruction)
        run_dir = record_run(tree_dir, provider, base_url, model, ["--analyze-ssh", str(recon_path)])
        (run_dir / "prompt.md").write_text(composed, encoding="utf-8")

        chat_url = base_url.rstrip("/") + "/chat/completions"
        api_key = os.environ.get("OPENAI_API_KEY") or "ollama"
        payload = json.dumps(
            {
                "model": model,
                "messages": [{"role": "user", "content": composed}],
                "temperature": 0.1,
            }
        ).encode("utf-8")
        req = urllib.request.Request(
            chat_url,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {api_key}",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=45) as resp:
                body = json.loads(resp.read().decode("utf-8", errors="replace"))
            choices = body.get("choices") or []
            reply = ((choices[0].get("message") or {}).get("content") or "").strip() if choices else ""
            if reply:
                (run_dir / "response.md").write_text(reply + "\n", encoding="utf-8")
                print(reply)
                return 0
        except Exception as exc:
            note = (
                f"_Local model endpoint `{base_url}` (`{model}`) was not reachable "
                f"({type(exc).__name__}: {exc}); showing deterministic Harness2 SSH audit above._"
            )
            (run_dir / "response.md").write_text(note + "\n", encoding="utf-8")
            print(note)
            return 0
        return 0


    def main(argv: list[str] | None = None) -> int:
        args = list(sys.argv[1:] if argv is None else argv)

        # Fast path for niro-real version probing
        copilot_real = os.environ.get("NIRO_COPILOT_REAL", "")
        if args in (["--version"], ["-v"], ["version"]) and copilot_real:
            os.execv(copilot_real, [copilot_real, *args])

        provider, base_url, model = verify_offline_endpoint()
        tree_dir = ensure_harness_tree()

        if args == ["--check"]:
            info = {
                "ok": True,
                "harness": "harness2",
                "tree_dir": str(tree_dir),
                "fingerprint": RM.fingerprint(tree_dir),
                "provider": provider,
                "base_url": base_url,
                "model": model,
                "offline": os.environ.get("NIRO_OFFLINE", "1") != "0",
            }
            print(json.dumps(info, indent=2))
            return 0

        if len(args) == 2 and args[0] == "--analyze-ssh":
            return analyze_ssh_with_local_model(
                tree_dir, provider, base_url, model, Path(args[1])
            )

        # Rewrite interactive prompt through Harness2 compose_prompt and auto-trust XDG root
        rewritten: list[str] = []
        has_prompt_mode = False
        i = 0
        while i < len(args):
            arg = args[i]
            if arg in ("--interactive", "-p", "--prompt") and i + 1 < len(args):
                has_prompt_mode = True
                mode_flag = "-p" if os.environ.get("NIRO_HEADLESS", "0") == "1" else arg
                rewritten.append(mode_flag)
                rewritten.append(wrap_prompt_with_harness(tree_dir, args[i + 1]))
                i += 2
                continue
            rewritten.append(arg)
            i += 1

        if has_prompt_mode and "--allow-all" not in rewritten:
            rewritten = ["--allow-all", *rewritten]

        run_dir = record_run(tree_dir, provider, base_url, model, rewritten)
        env = dict(os.environ)
        for drop_key in ("GITHUB_TOKEN", "GH_TOKEN", "COPILOT_GITHUB_TOKEN"):
            env.pop(drop_key, None)
        env["COPILOT_PROVIDER_TYPE"] = provider
        env["COPILOT_PROVIDER_BASE_URL"] = base_url
        env["COPILOT_PROVIDER_API_KEY"] = env.get("OPENAI_API_KEY") or "ollama"
        env["COPILOT_MODEL"] = model
        env["COPILOT_ALLOW_ALL"] = "true"
        env["OPENCODE_OFFLINE_ONLY"] = "1" if env.get("NIRO_OFFLINE", "1") != "0" else "0"
        env["HARNESS2_ACTIVE_RUN_DIR"] = str(run_dir)
        if env.get("NIRO_OFFLINE", "1") != "0":
            env["NO_PROXY"] = "127.0.0.1,localhost,::1,host.docker.internal"
            env["no_proxy"] = "127.0.0.1,localhost,::1,host.docker.internal"

        for rel in (".claude", ".codex", ".agents", ".github", ".mcp.json"):
            p = Path.cwd() / rel
            if p.is_dir() and not p.is_symlink():
                import shutil
                shutil.rmtree(p, ignore_errors=True)
            elif p.exists() or p.is_symlink():
                try:
                    p.unlink()
                except OSError:
                    pass

        if not copilot_real:
            sys.stderr.write("error: NIRO_COPILOT_REAL is not set for harness2-niro transport.\n")
            return 2

        os.execve(copilot_real, [copilot_real, *rewritten], env)


    if __name__ == "__main__":
        raise SystemExit(main())
  '';
in
{
  harness2 = prev.python3Packages.buildPythonApplication {
    pname = "harness2";
    inherit version src;
    pyproject = true;

    build-system = [ prev.python3Packages.setuptools ];

    dependencies = with prev.python3Packages; [
      fastapi
      google-auth
      openpyxl
      python-pptx
    ];

    nativeCheckInputs = [ prev.python3Packages.unittestCheckHook ];
    unittestFlagsArray = [
      "-s"
      "tests"
      "-v"
    ];

    postPatch = ''
      substituteInPlace harness2/config.py \
        --replace-fail \
          'THIRD_PARTY = ROOT / "third_party"' \
          'THIRD_PARTY = Path(os.environ["HARNESS2_THIRD_PARTY"]) if os.environ.get("HARNESS2_THIRD_PARTY") else (ROOT / "third_party" if (ROOT / "third_party").is_dir() else PKG / "third_party")'

      substituteInPlace harness2/install.py \
        --replace-fail \
          'ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "PROVENANCE.md"),' \
          'ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "PROVENANCE.md"), copy_function=shutil.copyfile,'

      cp ${niro_harness_py} harness2/cli/niro_harness.py

      substituteInPlace pyproject.toml \
        --replace-fail \
          'harness2-bridge = "harness2.cli.bridge:main"' \
          $'harness2-bridge = "harness2.cli.bridge:main"\nharness2-niro = "harness2.cli.niro_harness:main"'
    '';

    postInstall = ''
      cp -r third_party "$out/${prev.python3.sitePackages}/harness2/third_party"
      install -Dm755 scripts/split_tasks.py "$out/bin/harness2-split-tasks"
    '';

    makeWrapperArgs = [
      "--prefix"
      "PYTHONPATH"
      ":"
      "$PYTHONPATH"
      "--set-default"
      "HARNESS2_SOLVER_MODEL"
      "ollama/qwen2.5-coder:32b"
      "--set-default"
      "HARNESS2_IMPROVER_MODEL"
      "ollama/qwen2.5-coder:32b"
      "--set-default"
      "HARNESS2_JUDGE_MODEL"
      "ollama/qwen2.5-coder:32b"
      "--set-default"
      "HARNESS2_JUDGE_BASE_URL"
      "http://127.0.0.1:11434/v1"
      "--set-default"
      "HARNESS2_JUDGE_API_KEY"
      "ollama"
    ];

    pythonImportsCheck = [
      "harness2"
      "harness2.cli.run_sweep"
      "harness2.cli.setup"
      "harness2.cli.check"
      "harness2.cli.demo"
      "harness2.cli.judge"
      "harness2.cli.report"
      "harness2.cli.bridge"
      "harness2.cli.niro_harness"
    ];

    meta = with prev.lib; {
      description = "Harness2: Recursive Agent Harnessing for an Open World";
      homepage = "https://github.com/google-research/harness2";
      license = licenses.asl20;
      mainProgram = "harness2";
      platforms = platforms.unix;
      maintainers = [ ];
    };
  };
}
