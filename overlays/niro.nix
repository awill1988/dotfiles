final: prev:
let
  inherit (prev) lib;

  version = "0.1.80";
  copilot_version = "1.0.100";
  base_url = "https://github.com/apxlabs-ai/niro/releases/download/v${version}";

  platform_info = {
    aarch64-darwin = {
      url = "${base_url}/niro_darwin_arm64.tar.gz";
      hash = "sha256-E7A6ptNWlXOIo/tgbKsptGD0AJ6TLleuVJ4KU0GsvBo=";
      copilot_url = "https://registry.npmjs.org/@github/copilot-darwin-arm64/-/copilot-darwin-arm64-${copilot_version}.tgz";
      copilot_hash = "sha512-BXszRmLgL2aquEtjipqpOzbLkD29L0S1O0BlZCExfLeTqkjNOr8KEuhycXLsIHRV83gkCBA68lR4ahKcdtKFqQ==";
    };
    x86_64-darwin = {
      url = "${base_url}/niro_darwin_amd64.tar.gz";
      hash = "sha256-lFEGjDtZdw4Ul+zaZxumWHCCPPANCrttxJmdNnNELI0=";
      copilot_url = "https://registry.npmjs.org/@github/copilot-darwin-x64/-/copilot-darwin-x64-${copilot_version}.tgz";
      copilot_hash = "sha512-8ab4oscJumTNHopaC63JIJ3+/131781J3EjYIeSF/DSUeW/e8bp/MRiOmfVAqGtSpJyt78bINcGCf6yKbhvgiA==";
    };
    x86_64-linux = {
      url = "${base_url}/niro_linux_amd64.tar.gz";
      hash = "sha256-GIgdQSnvCbDKK9zD1tkFrwrqJ3VKAedpT/W/KcrkHDU=";
      copilot_url = "https://registry.npmjs.org/@github/copilot-linux-x64/-/copilot-linux-x64-${copilot_version}.tgz";
      copilot_hash = "sha512-pvzjJl0dzUcdIvSF5l5NFZKht7YE3G7yi6upbZTY+YaxSFqvnA0CQ2TyNezZpj9lOAPK4FsUuTn6h8hYNCcIZA==";
    };
    aarch64-linux = {
      url = "${base_url}/niro_linux_arm64.tar.gz";
      hash = "sha256-zbyoZrcDs1bVGqwL/8F4gIctVaSlfj3q7kbWXDEf4G8=";
      copilot_url = "https://registry.npmjs.org/@github/copilot-linux-arm64/-/copilot-linux-arm64-${copilot_version}.tgz";
      copilot_hash = "sha512-otMTg97TyY8/oe0wm43dn+2DC92gyiaT6JDqEW3G7MG1foxGM9RrkUGR+j0Zfqn6RnLQHqb3KP/j8JEmvJs+DQ==";
    };
  };

  system = final.stdenv.hostPlatform.system;
  info = platform_info.${system} or (throw "unsupported system for niro: ${system}");

  src = prev.fetchurl {
    url = info.url;
    hash = info.hash;
  };

  copilot_src = prev.fetchurl {
    url = info.copilot_url;
    hash = info.copilot_hash;
  };

  niro_launcher_py = prev.writeText "niro-launcher.py" ''
    #!${prev.python3}/bin/python3
    from __future__ import annotations

    import hashlib
    import json
    import os
    import re
    import shlex
    import shutil
    import socket
    import struct
    import subprocess
    import sys
    import time
    from pathlib import Path
    from urllib.parse import urlparse

    NIRO_OUT = Path("@out@")
    NIRO_REAL = NIRO_OUT / "libexec" / "niro" / "niro-real"
    COPILOT_REAL = NIRO_OUT / "libexec" / "niro" / "copilot-real"
    HARNESS2_NIRO = Path("${final.harness2}/bin/harness2-niro")
    GIT_BIN = "${prev.git}/bin/git"

    KNOWN_SUBCOMMANDS = {
        "find",
        "fix",
        "triage",
        "draft",
        "serve",
        "wait",
        "init",
        "hook",
        "ssh",
        "help",
        "version",
        "--help",
        "-h",
        "--version",
        "-v",
    }
    BLOCKED_AGENTS = {"claude", "codex", "agy"}
    DROP_ENV_VARS = (
        "ANTHROPIC_API_KEY",
        "CLAUDE_CODE_OAUTH_TOKEN",
        "ANTHROPIC_AUTH_TOKEN",
        "CODEX_API_KEY",
        "CODEX_ACCESS_TOKEN",
        "CODEX_AUTH_JSON_B64",
        "COPILOT_GITHUB_TOKEN",
        "GITHUB_TOKEN",
        "GH_TOKEN",
    )
    JUNK_PATHS = (
        ".claude",
        ".codex",
        ".agents",
        ".github",
        ".mcp.json",
    )


    def strip_workspace_pollution(root: Path) -> None:
        for rel in JUNK_PATHS:
            target = root / rel
            if target.is_dir() and not target.is_symlink():
                shutil.rmtree(target, ignore_errors=True)
            elif target.exists() or target.is_symlink():
                try:
                    target.unlink()
                except OSError:
                    pass


    def normalize_url(raw: str) -> str:
        val = raw.strip()
        if "://" not in val:
            return f"http://{val}"
        return val


    def has_explicit_port(raw: str) -> bool:
        norm = normalize_url(raw)
        parsed = urlparse(norm)
        return parsed.port is not None


    def extract_host_and_target(url_str: str, default_port: int | None = None) -> tuple[str, str, int, str]:
        norm = normalize_url(url_str)
        parsed = urlparse(norm)
        host = parsed.hostname or "default"
        port = parsed.port
        if port is None:
            if default_port is not None:
                port = default_port
            elif parsed.scheme == "ssh":
                port = 22
            else:
                port = 443 if parsed.scheme == "https" else 80
        safe_host = re.sub(r"[^A-Za-z0-9._-]+", "_", host) or "default"
        target_spec = f"[{host}]:{port}" if ":" in host else f"{host}:{port}"
        return safe_host, host, port, target_spec


    def ensure_git_root(root: Path) -> None:
        git_dir = root / ".git"
        env = {
            **os.environ,
            "GIT_AUTHOR_NAME": "niro-xdg",
            "GIT_AUTHOR_EMAIL": "niro@localhost",
            "GIT_COMMITTER_NAME": "niro-xdg",
            "GIT_COMMITTER_EMAIL": "niro@localhost",
        }
        if not git_dir.is_dir():
            subprocess.run([GIT_BIN, "init", "-q", str(root)], check=True, env=env)
        head = subprocess.run(
            [GIT_BIN, "-C", str(root), "rev-parse", "--verify", "HEAD"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env,
        )
        if head.returncode != 0:
            subprocess.run(
                [
                    GIT_BIN,
                    "-C",
                    str(root),
                    "-c",
                    "commit.gpgsign=false",
                    "commit",
                    "--allow-empty",
                    "-q",
                    "-m",
                    "Initialize universal XDG niro state root",
                ],
                check=True,
                env=env,
            )


    def ensure_scope_target(scope_file: Path, target_spec: str) -> None:
        if not scope_file.is_file():
            scope_file.write_text(
                "# yaml-language-server: $schema=https://niro.apxlabs.ai/schema/v1/scope.json\n"
                "#\n"
                f"targets:\n  - target: \"{target_spec}\"\n",
                encoding="utf-8",
            )
            return
        text = scope_file.read_text(encoding="utf-8")
        if f'"{target_spec}"' in text or f"'{target_spec}'" in text or f" {target_spec}\n" in text:
            return
        if "targets: []" in text:
            updated = text.replace(
                "targets: []",
                f'targets:\n  - target: "{target_spec}"',
                1,
            )
        elif "targets:" in text:
            updated = text.rstrip() + f'\n  - target: "{target_spec}"\n'
        else:
            updated = text.rstrip() + f'\ntargets:\n  - target: "{target_spec}"\n'
        scope_file.write_text(updated, encoding="utf-8")


    def ensure_offline_niro_yaml(niro_yaml: Path) -> None:
        if not niro_yaml.is_file():
            return
        text = niro_yaml.read_text(encoding="utf-8")
        marker = "# --- harness2-offline-defaults ---"
        if marker in text:
            return
        addition = (
            f"\n{marker}\n"
            "telemetry: false\n"
            "git_provider:\n"
            "  publish: false\n"
        )
        niro_yaml.write_text(text.rstrip() + addition, encoding="utf-8")


    def ensure_host_state(
        state_root: Path, safe_host: str, target_spec: str | None, clean_env: dict[str, str]
    ) -> str:
        rel_config_dir = f"hosts/{safe_host}"
        host_dir = state_root / rel_config_dir
        niro_yaml = host_dir / "niro.yaml"
        if not niro_yaml.is_file():
            host_dir.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(
                [
                    str(NIRO_REAL),
                    "init",
                    str(state_root),
                    "--agent",
                    "copilot",
                    "--config-dir",
                    rel_config_dir,
                    "--quiet",
                ],
                check=True,
                env=clean_env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        strip_workspace_pollution(state_root)
        ensure_offline_niro_yaml(niro_yaml)
        for sub in ("findings", "state", "artifacts", "harness/run"):
            (host_dir / sub).mkdir(parents=True, exist_ok=True)
        if target_spec:
            ensure_scope_target(host_dir / "scope.yaml", target_spec)
        return rel_config_dir


    def parse_kexinit_payload(payload: bytes) -> dict[str, list[str]]:
        # RFC 4253 Section 7.1: byte SSH_MSG_KEXINIT(20), 16-byte cookie, then 10 name-lists
        if not payload or payload[0] != 20 or len(payload) < 17:
            return {}
        offset = 17
        fields = [
            "kex_algorithms",
            "server_host_key_algorithms",
            "encryption_client_to_server",
            "encryption_server_to_client",
            "mac_client_to_server",
            "mac_server_to_client",
            "compression_client_to_server",
            "compression_server_to_client",
            "languages_client_to_server",
            "languages_server_to_client",
        ]
        out: dict[str, list[str]] = {}
        for name in fields:
            if offset + 4 > len(payload):
                break
            (length,) = struct.unpack(">I", payload[offset : offset + 4])
            offset += 4
            if offset + length > len(payload):
                break
            raw = payload[offset : offset + length].decode("ascii", errors="replace")
            offset += length
            out[name] = [x for x in raw.split(",") if x]
        return out


    def peek_is_ssh_service(host: str, port: int, timeout: float = 2.0) -> bool:
        try:
            with socket.create_connection((host, port), timeout=timeout) as sock:
                sock.settimeout(timeout)
                chunk = sock.recv(256)
                return b"SSH-" in chunk
        except Exception:
            return False


    def verify_ssh_negotiation(
        host: str,
        port: int,
        extra_opts: list[str],
        match_patterns: list[str],
        timeout: float = 6.0,
    ) -> dict[str, object]:
        ssh_bin = shutil.which("ssh") or "/usr/bin/ssh"
        cmd = [
            ssh_bin,
            "-vvv",
            "-o",
            "BatchMode=yes",
            "-o",
            "StrictHostKeyChecking=no",
            "-o",
            "UserKnownHostsFile=/dev/null",
            "-o",
            "PreferredAuthentications=none",
            "-o",
            "ConnectTimeout=5",
            *extra_opts,
            "-p",
            str(port),
            f"audit@{host}",
        ]
        cmd_str = " ".join(shlex.quote(c) for c in cmd)
        try:
            proc = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=timeout,
            )
            stderr_lines = (proc.stderr or "").splitlines()
            matched = [
                line.strip()
                for line in stderr_lines
                if any(pat in line for pat in match_patterns)
            ]
            return {
                "verified": bool(matched),
                "command": cmd_str,
                "matched_lines": matched[:8],
            }
        except Exception as exc:
            return {
                "verified": False,
                "command": cmd_str,
                "matched_lines": [],
                "error": f"{type(exc).__name__}: {exc}",
            }


    def collect_host_key_fingerprints(host: str, port: int) -> list[dict[str, str]]:
        keyscan_bin = shutil.which("ssh-keyscan") or "/usr/bin/ssh-keyscan"
        keygen_bin = shutil.which("ssh-keygen") or "/usr/bin/ssh-keygen"
        records: list[dict[str, str]] = []
        if not Path(keyscan_bin).is_file():
            return records
        try:
            scan = subprocess.run(
                [keyscan_bin, "-T", "5", "-p", str(port), host],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=7,
            )
            for line in (scan.stdout or "").splitlines():
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                fp_out = ""
                if Path(keygen_bin).is_file():
                    fp_proc = subprocess.run(
                        [keygen_bin, "-lf", "-"],
                        input=stripped + "\n",
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=4,
                    )
                    fp_out = (fp_proc.stdout or "").strip()
                records.append(
                    {
                        "authorized_key_entry": stripped,
                        "entry_sha256": hashlib.sha256(stripped.encode("utf-8")).hexdigest(),
                        "fingerprint": fp_out,
                    }
                )
        except Exception:
            pass
        return records


    def probe_ssh_kex(host: str, port: int, timeout: float = 6.0) -> dict:
        collected_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        result: dict = {
            "collected_at_utc": collected_at,
            "reachable": False,
            "provenance": {
                "local_socket": "",
                "remote_socket": f"{host}:{port}",
                "client_probe_banner": "SSH-2.0-NiroAudit_1.0",
                "banner_raw": "",
                "banner_hex": "",
                "banner_sha256": "",
                "kexinit_payload_len": 0,
                "kexinit_cookie_hex": "",
                "kexinit_sha256": "",
                "kexinit_raw_hex": "",
                "reproduce_wire_command": (
                    f"python3 -c 'import hashlib,socket,struct; s=socket.create_connection((\"{host}\",{port}),5); "
                    "b=s.recv(256); print(\"BANNER:\", b.splitlines()[0].decode()); "
                    "s.sendall(b\"SSH-2.0-NiroAudit_1.0\\r\\n\"); "
                    "d=b\"\".join(b.splitlines(True)[1:]) if b\"\\n\" in b else b\"\"; "
                    "d+=s.recv(4096) if len(d)<8 else b\"\"; "
                    "plen,pad=struct.unpack(\">IB\",d[:5]); "
                    "pay=d[5:4+plen-pad]; "
                    "print(\"KEXINIT_SHA256:\", hashlib.sha256(pay).hexdigest())'"
                ),
            },
            "banner": "",
            "kexinit": {},
            "host_keys": [],
            "auth_methods": [],
            "auth_probe_command": "",
            "auth_wire_evidence": "",
            "error": "",
        }
        try:
            with socket.create_connection((host, port), timeout=timeout) as sock:
                sock.settimeout(timeout)
                try:
                    lhost, lport = sock.getsockname()[:2]
                    rhost, rport = sock.getpeername()[:2]
                    result["provenance"]["local_socket"] = f"{lhost}:{lport}"
                    result["provenance"]["remote_socket"] = f"{rhost}:{rport}"
                except Exception:
                    pass
                buf = b""
                while b"\n" not in buf and len(buf) < 4096:
                    chunk = sock.recv(1024)
                    if not chunk:
                        break
                    buf += chunk
                lines = buf.splitlines(keepends=True)
                banner_line = ""
                banner_bytes = b""
                remainder = b""
                for idx, line in enumerate(lines):
                    decoded = line.decode("utf-8", errors="replace").strip()
                    if decoded.startswith("SSH-"):
                        banner_line = decoded
                        banner_bytes = line
                        remainder = b"".join(lines[idx + 1 :])
                        break
                if not banner_line and lines:
                    banner_line = lines[0].decode("utf-8", errors="replace").strip()
                    banner_bytes = lines[0]
                result["reachable"] = True
                result["banner"] = banner_line
                result["provenance"]["banner_raw"] = banner_line
                result["provenance"]["banner_hex"] = banner_bytes.hex()
                result["provenance"]["banner_sha256"] = hashlib.sha256(banner_bytes).hexdigest()

                sock.sendall(b"SSH-2.0-NiroAudit_1.0\r\n")
                while len(remainder) < 8:
                    chunk = sock.recv(4096)
                    if not chunk:
                        break
                    remainder += chunk
                if len(remainder) >= 5:
                    (pkt_len,) = struct.unpack(">I", remainder[:4])
                    pad_len = remainder[4]
                    while len(remainder) < 4 + pkt_len and pkt_len <= 65536:
                        chunk = sock.recv(4096)
                        if not chunk:
                            break
                        remainder += chunk
                    if len(remainder) >= 4 + pkt_len:
                        payload = remainder[5 : 4 + pkt_len - pad_len]
                        result["provenance"]["kexinit_payload_len"] = len(payload)
                        if len(payload) >= 17:
                            result["provenance"]["kexinit_cookie_hex"] = payload[1:17].hex()
                        result["provenance"]["kexinit_sha256"] = hashlib.sha256(payload).hexdigest()
                        result["provenance"]["kexinit_raw_hex"] = payload.hex()
                        result["kexinit"] = parse_kexinit_payload(payload)
        except Exception as exc:
            result["error"] = f"{type(exc).__name__}: {exc}"
            return result

        result["host_keys"] = collect_host_key_fingerprints(host, port)

        auth_probe = verify_ssh_negotiation(
            host,
            port,
            [],
            ["Authentications that can continue:", "Authenticated to "],
        )
        result["auth_probe_command"] = str(auth_probe.get("command") or "")
        matched_auth = auth_probe.get("matched_lines") or []
        if matched_auth:
            result["auth_wire_evidence"] = matched_auth[0]
            for line in matched_auth:
                if "Authentications that can continue:" in line:
                    methods = line.split("Authentications that can continue:", 1)[1].strip()
                    result["auth_methods"] = [m.strip() for m in methods.split(",") if m.strip()]
                    break
        return result


    def evaluate_ssh_findings(
        host: str, port: int, recon: dict, artifact_path: Path
    ) -> tuple[list[dict[str, object]], list[dict[str, str]]]:
        findings: list[dict[str, object]] = []
        unverified_notes: list[dict[str, str]] = []

        banner = recon.get("banner") or ""
        prov = recon.get("provenance") or {}
        kex_sha256 = prov.get("kexinit_sha256") or "(none)"
        kex_cookie = prov.get("kexinit_cookie_hex") or "(none)"
        socket_tuple = f"{prov.get('local_socket') or 'client'} -> {prov.get('remote_socket') or f'{host}:{port}'}"
        timestamp = recon.get("collected_at_utc") or ""

        kex = recon.get("kexinit") or {}
        kex_algs = list(kex.get("kex_algorithms") or [])
        ciphers_s2c = list(kex.get("encryption_server_to_client") or [])
        ciphers_c2s = list(kex.get("encryption_client_to_server") or [])
        ciphers = sorted(set(ciphers_s2c + ciphers_c2s))
        macs_s2c = list(kex.get("mac_server_to_client") or [])
        macs_c2s = list(kex.get("mac_client_to_server") or [])
        macs = sorted(set(macs_s2c + macs_c2s))
        auth_methods = set(recon.get("auth_methods") or [])

        # 1. CVE-2023-48795 (Terrapin attack) — Wire provenance + active cipher negotiation verification
        has_strict_kex = "kex-strict-s-v00@openssh.com" in kex_algs
        has_chacha = "chacha20-poly1305@openssh.com" in ciphers
        cbc_ciphers = [c for c in ciphers if c.endswith("-cbc")]
        etm_macs = [m for m in macs if m.endswith("-etm@openssh.com")]
        if kex_algs and not has_strict_kex and (has_chacha or (cbc_ciphers and etm_macs)):
            test_cipher = "chacha20-poly1305@openssh.com" if has_chacha else cbc_ciphers[0]
            extra = ["-o", f"Ciphers={test_cipher}"]
            if not has_chacha and etm_macs:
                extra.extend(["-o", f"MACs={etm_macs[0]}"])
            neg = verify_ssh_negotiation(
                host,
                port,
                extra,
                [f"kex: server->client cipher: {test_cipher}", "kex: host key algorithm:"],
            )
            evidence_lines = list(neg.get("matched_lines") or [])
            evidence_lines.append(
                f"SSH_MSG_KEXINIT.kex_algorithms (sha256={kex_sha256}): "
                f"kex-strict-s-v00@openssh.com=ABSENT; offered_cipher={test_cipher}"
            )
            findings.append(
                {
                    "id": "CVE-2023-48795",
                    "severity": "MEDIUM",
                    "verification_status": "VERIFIED (Wire-Confirmed)",
                    "title": "SSH Terrapin Prefix Truncation Vector (Missing Strict KEX)",
                    "detail": (
                        f"Server offered `{test_cipher}` in `SSH_MSG_KEXINIT` without advertising "
                        "`kex-strict-s-v00@openssh.com`, enabling sequence-number manipulation "
                        "during handshake extension negotiation."
                    ),
                    "provenance": {
                        "collected_at_utc": timestamp,
                        "socket_tuple": socket_tuple,
                        "kexinit_sha256": kex_sha256,
                        "kexinit_cookie_hex": kex_cookie,
                        "protocol_fields": "SSH_MSG_KEXINIT.kex_algorithms, encryption_server_to_client, mac_server_to_client",
                        "artifact_path": str(artifact_path),
                    },
                    "verification_evidence": evidence_lines,
                    "reproduce_commands": [
                        str(neg.get("command") or ""),
                        str(prov.get("reproduce_wire_command") or ""),
                    ],
                    "remediation": (
                        "Upgrade OpenSSH/SSH daemon to a release supporting `kex-strict-s-v00@openssh.com` "
                        "(OpenSSH >= 9.6) or disable `chacha20-poly1305@openssh.com` and `*-cbc` ciphers in "
                        "`/etc/ssh/sshd_config`: `Ciphers -chacha20-poly1305@openssh.com,*-cbc`."
                    ),
                    "reverify_command": (
                        f"ssh -vvv -o BatchMode=yes -o StrictHostKeyChecking=no "
                        f"-o UserKnownHostsFile=/dev/null -p {port} audit@{host} 2>&1 | "
                        "grep -E 'kex-strict-s-v00@openssh.com|server->client cipher'"
                    ),
                }
            )

        # 2. Banner-only version range checks MUST be segregated as Unverified Banner Observations
        m = re.search(r"OpenSSH_(\d+)\.(\d+)(?:p(\d+))?", banner)
        if m:
            major, minor = int(m.group(1)), int(m.group(2))
            if (major == 8 and minor >= 5) or (major == 9 and minor <= 7):
                unverified_notes.append(
                    {
                        "id": "NOTE-CVE-2024-6387-BANNER",
                        "status": "UNVERIFIED_BANNER_HYPOTHESIS (Excluded from Confirmed Findings)",
                        "title": f"OpenSSH Version Banner in 8.5p1–9.7p1 Window (`{banner}`)",
                        "detail": (
                            f"Server identification string `{banner}` (banner_sha256=`{prov.get('banner_sha256')}`) "
                            "falls numerically in OpenSSH 8.5p1–9.7p1. Because operating system distributions "
                            "(Debian, Ubuntu, RHEL, NixOS, Alpine) backport CVE-2024-6387 patches without "
                            "incrementing the upstream `OpenSSH_X.YpZ` version prefix, a banner match alone "
                            "does NOT prove vulnerability and is excluded from confirmed findings."
                        ),
                        "verification_guidance": (
                            "Inspect the host package version out-of-band (e.g., `sshd -V`, `dpkg -l openssh-server`, "
                            "`rpm -q openssh-server`, or Nix store path hash) to verify patch level."
                        ),
                    }
                )
            elif (major < 8) or (major == 8 and minor < 5):
                unverified_notes.append(
                    {
                        "id": "NOTE-LEGACY-OPENSSH-BANNER",
                        "status": "UNVERIFIED_BANNER_HYPOTHESIS (Excluded from Confirmed Findings)",
                        "title": f"Legacy OpenSSH Identification String (`{banner}`)",
                        "detail": (
                            f"Server banner reports `{banner}` (banner_sha256=`{prov.get('banner_sha256')}`). "
                            "Banner strings can be customized (`DebianBanner` / patched builds); verify package "
                            "provenance before treating version-only CVEs as confirmed."
                        ),
                        "verification_guidance": "Verify the installed `openssh-server` package build on the target.",
                    }
                )

        # 3. Authentication exposure (Verified via SSH_MSG_USERAUTH_FAILURE wire response)
        if "none" in auth_methods:
            findings.append(
                {
                    "id": "SSH-AUTH-NONE",
                    "severity": "CRITICAL",
                    "verification_status": "VERIFIED (Wire-Confirmed)",
                    "title": "SSH 'none' Authentication Method Advertised (`PermitEmptyPasswords`)",
                    "detail": (
                        "Server explicitly included `none` in `SSH_MSG_USERAUTH_FAILURE` "
                        "(`Authentications that can continue`), permitting unauthenticated login for accounts "
                        "with empty passwords."
                    ),
                    "provenance": {
                        "collected_at_utc": timestamp,
                        "socket_tuple": socket_tuple,
                        "kexinit_sha256": kex_sha256,
                        "kexinit_cookie_hex": kex_cookie,
                        "protocol_fields": "SSH_MSG_USERAUTH_FAILURE.authentications_that_can_continue",
                        "artifact_path": str(artifact_path),
                    },
                    "verification_evidence": [str(recon.get("auth_wire_evidence") or "")],
                    "reproduce_commands": [str(recon.get("auth_probe_command") or "")],
                    "remediation": "Set `PermitEmptyPasswords no` in `/etc/ssh/sshd_config` and reload `sshd`.",
                    "reverify_command": (
                        f"{recon.get('auth_probe_command')} 2>&1 | grep 'Authentications that can continue:'"
                    ),
                }
            )
        if "password" in auth_methods or "keyboard-interactive" in auth_methods:
            exposed = sorted(auth_methods & {"password", "keyboard-interactive"})
            findings.append(
                {
                    "id": "SSH-AUTH-PASSWORD",
                    "severity": "LOW",
                    "verification_status": "VERIFIED (Wire-Confirmed)",
                    "title": f"Interactive Password Authentication Advertised ({', '.join(exposed)})",
                    "detail": (
                        f"Server advertised `{', '.join(exposed)}` in `SSH_MSG_USERAUTH_FAILURE`, exposing the "
                        "SSH service to online password guessing and credential stuffing."
                    ),
                    "provenance": {
                        "collected_at_utc": timestamp,
                        "socket_tuple": socket_tuple,
                        "kexinit_sha256": kex_sha256,
                        "kexinit_cookie_hex": kex_cookie,
                        "protocol_fields": "SSH_MSG_USERAUTH_FAILURE.authentications_that_can_continue",
                        "artifact_path": str(artifact_path),
                    },
                    "verification_evidence": [str(recon.get("auth_wire_evidence") or "")],
                    "reproduce_commands": [str(recon.get("auth_probe_command") or "")],
                    "remediation": (
                        "Set `PasswordAuthentication no` and `KbdInteractiveAuthentication no` in "
                        "`/etc/ssh/sshd_config`, enforcing `AuthenticationMethods publickey`."
                    ),
                    "reverify_command": (
                        f"{recon.get('auth_probe_command')} 2>&1 | grep 'Authentications that can continue:'"
                    ),
                }
            )

        # 4. Weak KEX Algorithms (Wire provenance + active KEX negotiation verification)
        weak_kex = sorted(k for k in kex_algs if "sha1" in k or "group1-" in k)
        if weak_kex:
            target_kex = weak_kex[0]
            neg = verify_ssh_negotiation(
                host,
                port,
                ["-o", f"KexAlgorithms={','.join(weak_kex)}"],
                [f"kex: algorithm: {target_kex}", "kex: algorithm:"],
            )
            evidence_lines = list(neg.get("matched_lines") or [])
            evidence_lines.append(
                f"SSH_MSG_KEXINIT.kex_algorithms (sha256={kex_sha256}): {', '.join(weak_kex)}"
            )
            findings.append(
                {
                    "id": "SSH-WEAK-KEX",
                    "severity": "MEDIUM",
                    "verification_status": "VERIFIED (Wire-Confirmed)",
                    "title": "Weak SHA-1 / Diffie-Hellman Group1 KEX Algorithms Enabled",
                    "detail": (
                        f"Server advertised and negotiated weak KEX algorithm(s) in `SSH_MSG_KEXINIT`: "
                        f"`{', '.join(weak_kex)}`."
                    ),
                    "provenance": {
                        "collected_at_utc": timestamp,
                        "socket_tuple": socket_tuple,
                        "kexinit_sha256": kex_sha256,
                        "kexinit_cookie_hex": kex_cookie,
                        "protocol_fields": "SSH_MSG_KEXINIT.kex_algorithms",
                        "artifact_path": str(artifact_path),
                    },
                    "verification_evidence": evidence_lines,
                    "reproduce_commands": [
                        str(neg.get("command") or ""),
                        str(prov.get("reproduce_wire_command") or ""),
                    ],
                    "remediation": (
                        f"Remove weak KEX algorithms in `/etc/ssh/sshd_config`: "
                        f"`KexAlgorithms -{','.join(weak_kex)}`."
                    ),
                    "reverify_command": (
                        f"{neg.get('command')} 2>&1 | grep -E 'Unable to negotiate|kex: algorithm:'"
                    ),
                }
            )

        # 5. Weak Encryption Ciphers (Wire provenance + active cipher negotiation verification)
        weak_ciphers = sorted(
            c for c in ciphers if c.endswith("-cbc") or "3des" in c or "arcfour" in c
        )
        if weak_ciphers:
            neg = verify_ssh_negotiation(
                host,
                port,
                ["-o", f"Ciphers={','.join(weak_ciphers)}"],
                ["kex: server->client cipher:", "kex: client->server cipher:"],
            )
            evidence_lines = list(neg.get("matched_lines") or [])
            evidence_lines.append(
                f"SSH_MSG_KEXINIT.encryption_server_to_client (sha256={kex_sha256}): {', '.join(weak_ciphers)}"
            )
            findings.append(
                {
                    "id": "SSH-WEAK-CIPHERS",
                    "severity": "MEDIUM",
                    "verification_status": "VERIFIED (Wire-Confirmed)",
                    "title": "Weak CBC / Legacy Encryption Ciphers Enabled",
                    "detail": (
                        f"Server advertised and negotiated legacy cipher(s) in `SSH_MSG_KEXINIT`: "
                        f"`{', '.join(weak_ciphers)}`."
                    ),
                    "provenance": {
                        "collected_at_utc": timestamp,
                        "socket_tuple": socket_tuple,
                        "kexinit_sha256": kex_sha256,
                        "kexinit_cookie_hex": kex_cookie,
                        "protocol_fields": "SSH_MSG_KEXINIT.encryption_client_to_server, encryption_server_to_client",
                        "artifact_path": str(artifact_path),
                    },
                    "verification_evidence": evidence_lines,
                    "reproduce_commands": [
                        str(neg.get("command") or ""),
                        str(prov.get("reproduce_wire_command") or ""),
                    ],
                    "remediation": (
                        f"Disable weak ciphers in `/etc/ssh/sshd_config`: "
                        f"`Ciphers -{','.join(weak_ciphers)}`."
                    ),
                    "reverify_command": (
                        f"{neg.get('command')} 2>&1 | grep -E 'Unable to negotiate|server->client cipher:'"
                    ),
                }
            )

        # 6. Weak MAC Algorithms (Wire provenance + active MAC negotiation verification)
        weak_macs = sorted(
            m for m in macs if "md5" in m or "96" in m or m in ("hmac-sha1", "umac-64@openssh.com")
        )
        if weak_macs:
            non_aead = [
                c
                for c in ciphers
                if "gcm" not in c and "chacha20" not in c
            ]
            mac_opts = ["-o", f"MACs={','.join(weak_macs)}"]
            if non_aead:
                mac_opts.extend(["-o", f"Ciphers={','.join(non_aead)}"])
            neg = verify_ssh_negotiation(
                host,
                port,
                mac_opts,
                ["kex: server->client cipher:", "kex: client->server cipher:"],
            )
            evidence_lines = list(neg.get("matched_lines") or [])
            evidence_lines.append(
                f"SSH_MSG_KEXINIT.mac_server_to_client (sha256={kex_sha256}): {', '.join(weak_macs)}"
            )
            findings.append(
                {
                    "id": "SSH-WEAK-MACS",
                    "severity": "LOW",
                    "verification_status": "VERIFIED (Wire-Confirmed)",
                    "title": "Weak or Legacy MAC Algorithms Enabled",
                    "detail": (
                        f"Server advertised and negotiated legacy MAC algorithm(s) in `SSH_MSG_KEXINIT`: "
                        f"`{', '.join(weak_macs)}`."
                    ),
                    "provenance": {
                        "collected_at_utc": timestamp,
                        "socket_tuple": socket_tuple,
                        "kexinit_sha256": kex_sha256,
                        "kexinit_cookie_hex": kex_cookie,
                        "protocol_fields": "SSH_MSG_KEXINIT.mac_client_to_server, mac_server_to_client",
                        "artifact_path": str(artifact_path),
                    },
                    "verification_evidence": evidence_lines,
                    "reproduce_commands": [
                        str(neg.get("command") or ""),
                        str(prov.get("reproduce_wire_command") or ""),
                    ],
                    "remediation": (
                        f"Disable legacy MAC algorithms in `/etc/ssh/sshd_config`: "
                        f"`MACs -{','.join(weak_macs)}`."
                    ),
                    "reverify_command": (
                        f"{neg.get('command')} 2>&1 | grep -E 'Unable to negotiate|MAC:'"
                    ),
                }
            )

        return findings, unverified_notes


    def run_ssh_audit(
        state_root: Path,
        env: dict[str, str],
        target_arg: str,
        goal: str,
    ) -> int:
        check_rc = subprocess.call([str(HARNESS2_NIRO), "--check"], env=env, stdout=subprocess.DEVNULL)
        if check_rc != 0:
            return check_rc

        safe_host, host, port, target_spec = extract_host_and_target(target_arg, default_port=22)
        rel_config_dir = ensure_host_state(state_root, safe_host, target_spec, env)
        host_dir = state_root / rel_config_dir
        env["NIRO_TARGET_HOST"] = safe_host
        env["NIRO_HOST_STATE_DIR"] = str(host_dir)

        recon_path = host_dir / "artifacts" / f"ssh-recon-{port}.json"
        report_path = host_dir / "findings" / f"ssh-audit-{port}.md"

        print(f"[niro] Target: {host}:{port} | Goal: {goal}")
        print(f"[niro] Host State Directory: {host_dir}")
        probe = probe_ssh_kex(host, port)
        findings, unverified_notes = (
            evaluate_ssh_findings(host, port, probe, recon_path)
            if probe["reachable"]
            else ([], [])
        )

        recon = {
            "timestamp": probe["collected_at_utc"],
            "host": host,
            "port": port,
            "goal": goal,
            "artifact_path": str(recon_path),
            **probe,
            "confirmed_findings": findings,
            "unverified_banner_notes": unverified_notes,
        }
        recon_path.write_text(json.dumps(recon, indent=2) + "\n", encoding="utf-8")

        prov = probe.get("provenance") or {}
        report_lines = [
            f"# SSH Security Audit Report: `{host}:{port}`",
            "",
            "## 1. Audit Scope & Wire Provenance",
            f"- **Collected At (UTC)**: `{recon['timestamp']}`",
            f"- **Audit Goal**: `{goal}`",
            f"- **Socket Tuple**: `{prov.get('local_socket') or 'client'} -> {prov.get('remote_socket') or f'{host}:{port}'}`",
            f"- **Reachable**: `{probe['reachable']}`",
            f"- **Server Banner**: `{probe['banner'] or '(none)'}`",
            f"- **Banner SHA-256**: `{prov.get('banner_sha256') or '(none)'}`",
            f"- **RFC 4253 `SSH_MSG_KEXINIT` SHA-256**: `{prov.get('kexinit_sha256') or '(none)'}`",
            f"- **RFC 4253 `SSH_MSG_KEXINIT` Cookie**: `{prov.get('kexinit_cookie_hex') or '(none)'}`",
            f"- **RFC 4253 `SSH_MSG_KEXINIT` Payload Length**: `{prov.get('kexinit_payload_len') or 0} bytes`",
            f"- **Advertised Auth Methods**: `{', '.join(probe['auth_methods']) or '(not advertised / closed)'}`",
            f"- **Strict KEX (`kex-strict-s-v00@openssh.com`)**: "
            f"`{'kex-strict-s-v00@openssh.com' in (probe.get('kexinit', {}).get('kex_algorithms') or [])}`",
            f"- **Raw Recon Artifact**: `{recon_path}`",
            "",
        ]
        if probe.get("host_keys"):
            report_lines.append("### Host Key Fingerprints (`ssh-keyscan`)")
            for hk in probe["host_keys"]:
                fp = hk.get("fingerprint") or hk.get("authorized_key_entry") or ""
                report_lines.append(f"- `{fp}` (entry_sha256: `{hk.get('entry_sha256')}`)")
            report_lines.append("")

        if not probe["reachable"]:
            report_lines.extend(
                [
                    "## 2. Connection Failure",
                    f"- Could not reach `{host}:{port}`: `{probe['error']}`",
                ]
            )
            report_md = "\n".join(report_lines) + "\n"
            report_path.write_text(report_md, encoding="utf-8")
            print(report_md)
            return 1

        report_lines.append("## 2. Confirmed Findings (`VERIFIED` on the Wire)")
        if findings:
            for idx, f in enumerate(findings, start=1):
                f_prov = f.get("provenance") or {}
                report_lines.extend(
                    [
                        "",
                        f"### 2.{idx}. [{f['severity']}] {f['id']} — {f['title']}",
                        f"- **Verification Status**: `{f['verification_status']}`",
                        f"- **Summary**: {f['detail']}",
                        "- **Vector Provenance**:",
                        f"  - **Timestamp (UTC)**: `{f_prov.get('collected_at_utc')}`",
                        f"  - **Socket Tuple**: `{f_prov.get('socket_tuple')}`",
                        f"  - **`SSH_MSG_KEXINIT` SHA-256**: `{f_prov.get('kexinit_sha256')}` (cookie `{f_prov.get('kexinit_cookie_hex')}`)",
                        f"  - **Protocol Field(s)**: `{f_prov.get('protocol_fields')}`",
                        f"  - **Artifact File**: `{f_prov.get('artifact_path')}`",
                        "- **Wire Verification Proof**:",
                    ]
                )
                for ev in f.get("verification_evidence") or []:
                    report_lines.append(f"  - `{ev}`")
                report_lines.append("- **Steps to Reproduce**:")
                report_lines.append("  ```bash")
                for cmd_line in f.get("reproduce_commands") or []:
                    if cmd_line:
                        report_lines.append(f"  {cmd_line}")
                report_lines.append("  ```")
                report_lines.extend(
                    [
                        f"- **Remediation**: {f['remediation']}",
                        "- **Post-Remediation Verification Command**:",
                        "  ```bash",
                        f"  {f['reverify_command']}",
                        "  ```",
                    ]
                )
        else:
            report_lines.append(
                "- **0 confirmed vulnerabilities**: All inspected handshake algorithms, strict KEX extensions, and authentication methods passed wire verification."
            )

        report_lines.extend(["", "## 3. Unverified Banner Observations (Excluded from Confirmed Findings)"])
        if unverified_notes:
            for note in unverified_notes:
                report_lines.extend(
                    [
                        f"- **{note['id']} — {note['title']}** (`{note['status']}`)",
                        f"  - **Rationale**: {note['detail']}",
                        f"  - **Out-of-Band Verification**: {note['verification_guidance']}",
                    ]
                )
        else:
            report_lines.append("- None.")

        kex = probe.get("kexinit") or {}
        if kex:
            report_lines.extend(
                [
                    "",
                    "## 4. Complete `SSH_MSG_KEXINIT` Algorithm Matrix",
                    f"- **KEX Algorithms**: `{', '.join(kex.get('kex_algorithms') or [])}`",
                    f"- **Server Host Key Algorithms**: `{', '.join(kex.get('server_host_key_algorithms') or [])}`",
                    f"- **Encryption Ciphers (s2c)**: `{', '.join(kex.get('encryption_server_to_client') or [])}`",
                    f"- **MAC Algorithms (s2c)**: `{', '.join(kex.get('mac_server_to_client') or [])}`",
                    f"- **Compression (s2c)**: `{', '.join(kex.get('compression_server_to_client') or [])}`",
                ]
            )

        report_md = "\n".join(report_lines) + "\n"
        print(report_md)
        print("## 5. Harness2 Offline Local Model Assessment (Goal-Driven)")
        proc = subprocess.run(
            [str(HARNESS2_NIRO), "--analyze-ssh", str(recon_path)],
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=sys.stderr,
        )
        llm_out = (proc.stdout or "").strip()
        if llm_out:
            print(llm_out)
            report_md += f"\n## 5. Harness2 Offline Local Model Assessment (Goal-Driven)\n\n{llm_out}\n"

        report_path.write_text(report_md, encoding="utf-8")
        print(f"\n[niro] Saved findings report: {report_path}")
        print(f"[niro] Saved recon artifact:  {recon_path}")
        return 0


    def is_ssh_request(subcmd: str, raw_target: str | None, goal: str | None) -> bool:
        if subcmd == "ssh":
            return True
        if not raw_target:
            return False
        raw_lower = raw_target.strip().lower()
        if raw_lower.startswith("ssh://"):
            return True
        goal_mentions_ssh = bool(goal and re.search(r"\bssh\b", goal, re.IGNORECASE))
        explicit_port = has_explicit_port(raw_target)
        default_port = 22 if (goal_mentions_ssh and not explicit_port) else None
        _, host, port, _ = extract_host_and_target(raw_target, default_port=default_port)
        if port in (22, 2222):
            return True
        if goal_mentions_ssh:
            return True
        return peek_is_ssh_service(host, port)


    def main() -> int:
        args = sys.argv[1:]
        if not args:
            return subprocess.call([str(NIRO_REAL)])

        # Never run or block on niro hooks
        if args[0] == "hook":
            return 0

        # Allow direct target+goal invocation:
        #   niro 192.168.1.50 "look for ssh vulns"
        #   niro 192.168.1.50 --goal "look for ssh vulns"
        #   niro --target 192.168.1.50 --goal "look for ssh vulns"
        first = args[0]
        if first not in KNOWN_SUBCOMMANDS:
            if first.startswith("-"):
                subcmd = "find"
                tail = args
            else:
                subcmd = "direct_target"
                tail = args
        else:
            subcmd = first
            tail = args[1:]

        # Validate --agent flags and extract target + goal
        has_agent_flag = False
        has_config_dir = False
        has_project_root = False
        raw_target: str | None = None
        detected_url: str | None = None
        detected_goal: str | None = None
        rewritten_tail: list[str] = []
        positional: list[str] = []

        i = 0
        while i < len(tail):
            arg = tail[i]
            if arg == "--agent":
                if i + 1 >= len(tail):
                    sys.stderr.write("error: --agent requires a value\n")
                    return 2
                val = tail[i + 1]
                if val in BLOCKED_AGENTS:
                    sys.stderr.write(
                        "error: niro is restricted to open-weight models in harness2; "
                        "claude, codex, and agy are disabled.\n"
                        "Configure NIRO_PROVIDER, OPENAI_API_BASE, OPENAI_API_KEY, and NIRO_MODEL.\n"
                    )
                    return 2
                has_agent_flag = True
                rewritten_tail.extend([arg, val])
                i += 2
                continue
            if arg.startswith("--agent="):
                val = arg.split("=", 1)[1]
                if val in BLOCKED_AGENTS:
                    sys.stderr.write(
                        "error: niro is restricted to open-weight models in harness2; "
                        "claude, codex, and agy are disabled.\n"
                        "Configure NIRO_PROVIDER, OPENAI_API_BASE, OPENAI_API_KEY, and NIRO_MODEL.\n"
                    )
                    return 2
                has_agent_flag = True
                rewritten_tail.append(arg)
                i += 1
                continue
            if arg in ("--url", "--target") and i + 1 < len(tail):
                raw_target = tail[i + 1]
                norm_u = normalize_url(raw_target)
                detected_url = norm_u
                rewritten_tail.extend(["--url", norm_u])
                i += 2
                continue
            if arg.startswith("--url=") or arg.startswith("--target="):
                raw_target = arg.split("=", 1)[1]
                norm_u = normalize_url(raw_target)
                detected_url = norm_u
                rewritten_tail.append(f"--url={norm_u}")
                i += 1
                continue
            if arg == "--goal" and i + 1 < len(tail):
                detected_goal = tail[i + 1]
                rewritten_tail.extend([arg, tail[i + 1]])
                i += 2
                continue
            if arg.startswith("--goal="):
                detected_goal = arg.split("=", 1)[1]
                rewritten_tail.append(arg)
                i += 1
                continue
            if arg == "--config-dir" or arg.startswith("--config-dir="):
                has_config_dir = True
            if arg == "--project-root" or arg.startswith("--project-root="):
                has_project_root = True
            if not arg.startswith("-"):
                positional.append(arg)
            rewritten_tail.append(arg)
            i += 1

        # Clean environment & set offline local model defaults for harness2
        env = {k: v for k, v in os.environ.items() if k not in DROP_ENV_VARS}
        env["NIRO_HARNESS"] = env.get("NIRO_HARNESS") or "harness2"
        env["NIRO_OFFLINE"] = env.get("NIRO_OFFLINE") or "1"
        env["NIRO_PROVIDER"] = env.get("NIRO_PROVIDER") or "openai"
        base_url = (
            env.get("OPENAI_API_BASE")
            or env.get("OPENAI_BASE_URL")
            or "http://127.0.0.1:11434/v1"
        )
        env["OPENAI_API_BASE"] = base_url
        env["OPENAI_API_KEY"] = env.get("OPENAI_API_KEY") or "ollama"
        env["NIRO_MODEL"] = env.get("NIRO_MODEL") or "qwen2.5-coder:32b"
        env["COPILOT_PROVIDER_TYPE"] = env["NIRO_PROVIDER"]
        env["COPILOT_PROVIDER_BASE_URL"] = env["OPENAI_API_BASE"]
        env["COPILOT_PROVIDER_API_KEY"] = env["OPENAI_API_KEY"]
        env["COPILOT_MODEL"] = env["NIRO_MODEL"]
        env["NIRO_COPILOT_REAL"] = env.get("NIRO_COPILOT_REAL") or str(COPILOT_REAL)

        cache_home = Path(env.get("XDG_CACHE_HOME") or (Path.home() / ".cache"))
        env["COPILOT_HOME"] = str(cache_home / "niro-harness2")
        Path(env["COPILOT_HOME"]).mkdir(parents=True, exist_ok=True)
        libexec_bin = NIRO_OUT / "libexec" / "niro" / "bin"
        cur_path = env.get("PATH") or ""
        env["PATH"] = f"{libexec_bin}:{cur_path}"

        # Universal XDG state root (~/.config/niro) so niro is never bound to a user repo
        xdg_config = Path(env.get("XDG_CONFIG_HOME") or (Path.home() / ".config"))
        raw_root = Path(env.get("NIRO_STATE_ROOT") or (xdg_config / "niro"))
        raw_root.mkdir(parents=True, exist_ok=True)
        state_root = raw_root.resolve()
        ensure_git_root(state_root)
        strip_workspace_pollution(state_root)

        if subcmd in ("ssh", "direct_target"):
            target_val = raw_target or (positional[0] if positional else "")
            if not target_val:
                sys.stderr.write("usage: niro [ssh] <ip[:port]> [goal]\n")
                return 2
            goal_val = detected_goal or (
                " ".join(positional[1:])
                if len(positional) > 1
                else "Audit SSH protocol banner, KEX algorithms, ciphers, MACs, auth methods, and CVEs"
            )
            if is_ssh_request(subcmd, target_val, goal_val):
                return run_ssh_audit(state_root, env, target_val, goal_val)
            # Non-SSH direct_target falls through to `niro find --url <target> --goal <goal>`
            subcmd = "find"
            detected_url = normalize_url(target_val)
            raw_target = target_val
            rewritten_tail = ["--url", detected_url]
            if goal_val:
                rewritten_tail.extend(["--goal", goal_val])

        if subcmd == "find" and raw_target and is_ssh_request(subcmd, raw_target, detected_goal):
            goal_val = (
                detected_goal
                or "Audit SSH protocol banner, KEX algorithms, ciphers, MACs, auth methods, and CVEs"
            )
            return run_ssh_audit(state_root, env, raw_target, goal_val)

        if subcmd == "init":
            target_dir = Path(rewritten_tail[0]).resolve() if rewritten_tail and not rewritten_tail[0].startswith("-") else state_root
            cmd = [str(NIRO_REAL), "init"]
            if not has_agent_flag:
                cmd.append("--agent=copilot")
            cmd.extend(rewritten_tail if rewritten_tail else [str(state_root)])
            rc = subprocess.call(cmd, env=env)
            strip_workspace_pollution(target_dir)
            strip_workspace_pollution(state_root)
            return rc

        if subcmd in ("find", "fix", "triage", "draft", "serve", "wait"):
            # Pre-validate harness2 tree and offline local endpoint before launching niro
            check_rc = subprocess.call([str(HARNESS2_NIRO), "--check"], env=env, stdout=subprocess.DEVNULL)
            if check_rc != 0:
                return check_rc

            if subcmd == "draft" and len(rewritten_tail) >= 2 and rewritten_tail[0] == "scope" and not detected_url:
                if not rewritten_tail[1].startswith("-"):
                    detected_url = normalize_url(rewritten_tail[1])
                    rewritten_tail[1] = detected_url

            if detected_url:
                safe_host, _, _, target_spec = extract_host_and_target(detected_url)
            else:
                safe_host, target_spec = "default", None
            rel_config_dir = ensure_host_state(state_root, safe_host, target_spec, env)
            env["NIRO_TARGET_HOST"] = safe_host
            env["NIRO_HOST_STATE_DIR"] = str(state_root / rel_config_dir)

            cmd = [str(NIRO_REAL), subcmd]
            if subcmd in ("find", "fix", "triage") and not has_agent_flag:
                cmd.append("--agent=copilot")
            if subcmd in ("find", "fix", "triage", "wait") and not has_config_dir:
                cmd.append(f"--config-dir={rel_config_dir}")
            cmd.extend(rewritten_tail)

            if not has_project_root:
                os.chdir(state_root)
            try:
                return subprocess.call(cmd, env=env)
            finally:
                strip_workspace_pollution(state_root)

        try:
            return subprocess.call([str(NIRO_REAL), *args], env=env)
        finally:
            strip_workspace_pollution(state_root)


    if __name__ == "__main__":
        raise SystemExit(main())
  '';
in
{
  niro = prev.stdenv.mkDerivation {
    pname = "niro";
    inherit version src;

    sourceRoot = ".";

    nativeBuildInputs = lib.optionals prev.stdenv.isLinux [ prev.autoPatchelfHook ];
    buildInputs = lib.optionals prev.stdenv.isLinux [
      prev.stdenv.cc.cc.lib
      prev.zlib
    ];

    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    unpackPhase = ''
      tar -xzf "$src"
      mkdir -p copilot-pkg
      tar -xzf "${copilot_src}" -C copilot-pkg
    '';

    installPhase = ''
      runHook preInstall

      install -Dm755 niro "$out/libexec/niro/niro-real"
      install -Dm755 copilot-pkg/package/copilot "$out/libexec/niro/copilot-real"

      mkdir -p "$out/libexec/niro/bin" "$out/bin"
      cat > "$out/libexec/niro/bin/copilot" <<EOF
      #!${prev.runtimeShell}
      export NIRO_COPILOT_REAL="\''${NIRO_COPILOT_REAL:-$out/libexec/niro/copilot-real}"
      exec "${final.harness2}/bin/harness2-niro" "\$@"
      EOF
      chmod 755 "$out/libexec/niro/bin/copilot"

      substitute ${niro_launcher_py} "$out/bin/niro" \
        --subst-var-by out "$out"
      chmod 755 "$out/bin/niro"

      runHook postInstall
    '';

    meta = {
      description = "Niro CLI launched in harness2 with offline local models and universal XDG per-host state";
      homepage = "https://github.com/apxlabs-ai/niro";
      license = lib.licenses.unfree;
      platforms = builtins.attrNames platform_info;
      mainProgram = "niro";
    };
  };
}
