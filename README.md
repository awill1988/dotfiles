# Developer Toolchain & Multi-Profile Nix Configuration

Personal dotfiles and developer toolchain managed with [Nix](https://nixos.org/), supporting **macOS** (via `nix-darwin`) and **WSL Linux / Debian** (via `home-manager`).

---

## Key Features

- **4-Layer Resolution Architecture**:
  - `Layer 1: Baseline Defaults` — Core identity (`fullName`, GPG/SSH key, default region, base git settings).
  - `Layer 2: Developer Profiles` — Identity boundaries (`personal`, `work`, `yourmoodai`) with isolated XDG config stores (`~/.config/profiles/<profile>/`).
  - `Layer 3: Host / Machine Layer` — Machine-specific OS usernames (`adam` vs `adam.williams`), platform types, and default fallbacks.
  - `Layer 4: Per-Folder Overrides` — Subfolder diffs (e.g. `~/projects/arro/security-audit`) overlaying custom role ARNs, gitconfig settings, or MCP tools.
- **Dynamic CWD Auto-Routing (`profile-router`)**:
  - Automatically matches Current Working Directory against profile path prefixes (`~/projects/arro`, `~/projects/personal`, etc.).
  - Sets `$DEVELOPER_PROFILE`, `$CODE_AGENT`, `$CLAUDE_CONFIG_DIR`, `$GEMINI_CONFIG_DIR`, `$CODEX_CONFIG_DIR`, `$AGY_CONFIG_DIR`, `$AWS_PROFILE`, `$AWS_REGION`, and Git author details dynamically on execution.
- **`direnv` / `nix-direnv` Integration**: Provides `use_profile <name>` helper for explicit per-project `.envrc` overrides.
- **First-Class MCP Tool Gateway (`contextforge`)**: Unified agent tools gateway and sidecar manager.

---

## Platform Activation & Permissions

| Target Platform | Toolchain Manager | Permissions | Command |
| :--- | :--- | :--- | :--- |
| **macOS** (`aarch64-darwin`) | `nix-darwin` | **System Root (`sudo`)** | `sudo ./result/sw/bin/darwin-rebuild switch --flake .#macbook-personal` |
| **WSL / Debian Linux** (`x86_64-linux`) | `home-manager` | **User Space (No Root)** | `nix build .#homeConfigurations.wsl-debian-personal.activationPackage && ./result/activate` |

---

## Quick Start

### 1. macOS (first-time setup)

```bash
# Build bootstrap closure
nix --extra-experimental-features 'nix-command flakes' build .#darwinConfigurations.bootstrap-arm.system

# Activate system-wide configuration
sudo ./result/sw/bin/darwin-rebuild switch --flake .#macbook-personal
```

### 2. WSL / Debian Linux (standalone user-space)

```bash
# Build and activate Home-Manager generation (no sudo required)
nix --extra-experimental-features 'nix-command flakes' build .#homeConfigurations.wsl-debian-personal.activationPackage && ./result/activate
```

---

## Customizing Identities, Profiles & Hosts (`userinfo.nix`)

All identity details, profiles, machine definitions, and path overrides are declared cleanly in `userinfo.nix`.

```nix
{ lib }:
{
  # Layer 1: Global Baseline Defaults
  baseline = {
    identity = {
      fullName = "Adam Williams";
      github = "awill1988";
      signingKey = "4A0DB07DEDB705FBA45F557B7A0F7A351FABE619";
      signingFormat = "ssh";
      email = "adam@williams.engineer";
    };
    aws = {
      region = "us-east-1";
      profile = "personal";
    };
  };

  # Layer 3: Machine / Host Layer (Decoupled OS Username)
  hosts = {
    "macbook-personal" = {
      username = "adam";
      system = "aarch64-darwin";
      homeDirectory = "/Users/adam";
      primaryProfile = "personal";
    };

    "wsl-debian-personal" = {
      username = "adam";
      system = "x86_64-linux";
      homeDirectory = "/home/adam";
      primaryProfile = "personal";
    };
  };

  # Layer 2: Developer Profiles Matrix
  profiles = {
    personal = {
      isPrimary = true;
      pathPrefixes = [
        "~/projects/personal"
        "~/projects/awill1988"
      ];
    };

    work = {
      identity.email = "adam@arrofinance.com";
      pathPrefixes = [ "~/projects/arro" ];
      aws = {
        profile = "arro-staging";
        region = "us-west-2";
      };
      agents.claude = {
        excludeMcpServers = [ "blender" ];
        mcpServers = {
          atlassian = { command = "npx"; args = [ "-y" "mcp-remote" "https://mcp.atlassian.com/v1/mcp" ]; };
          linear = { command = "npx"; args = [ "-y" "mcp-remote" "https://mcp.linear.app/mcp" ]; };
        };
      };
    };
  };

  # Layer 4: Per-Folder Overrides
  folderOverrides = {
    "~/projects/arro/security-audit" = {
      inherits = "work";
      aws.profile = "arro-audit-role";
      env = {
        SECURITY_AUDIT_ACTIVE = "1";
      };
    };
  };
}
```

---

## Validation & Formatting

```bash
# Format all Nix files
nix fmt

# Validate flake outputs & overlays
nix flake check
```

## Shared Instructions

[`awill1988/prompts`](https://github.com/awill1988/prompts) owns shared engineering
and technology policies. Every developer profile receives the same document.
This repository retains identity routing, permitted tools, credentials, and
installation. Profile-specific configuration remains in `userinfo.nix`; changing
shared instructions does not expand authorized accounts or clients.

The non-flake `prompts` input provides shared instructions through its
`instructions/AGENTS.md` interface, replacing three client instruction copies.
Repository-local `AGENTS.md`, `CLAUDE.md`, and `AGY.md` remain repository guidance.

### Update and verification

Update only the prompt input from a merged prompts revision:

```sh
nix flake update prompts
nix build .#checks.aarch64-darwin.agent-prompts
nix flake check
nix build .#darwinConfigurations.macbook-personal.system
```

On Linux, use `checks.x86_64-linux.agent-prompts` and build
`homeConfigurations.wsl-debian-personal.activationPackage`. Review and commit
the lock change before activating through the platform procedure above. A
published prompts commit alone never changes installed instructions.

All consumers use `modules.agents.agent-prompts.instructionsSource`, whose
default comes from the pinned input. The module honors resolved client
`configDir` settings and runs after profile-directory setup. Installed canonical
files have mode `0600`; profile client filenames are aliases to the shared
installed canonical file. Global Codex and AGY links remain managed by Home
Manager and reference the same pinned source, preserving generation rollback.
Activation does not fetch from Git.

### Migration and rollback

The cutover validates destinations before replacing files and backs up displaced
content under `$XDG_STATE_HOME/agent-prompts/backups` (normally
`~/.local/state/agent-prompts/backups`). Each backup directory includes `path.txt`
identifying the original destination. Repeated activation is idempotent.

After activation, compare installed content and aliases with the locked source
for every enabled client and configured profile. Keep the previous generation
available until these checks pass.

For a prompt-only rollback, restore the preceding `prompts` lock entry through a
reviewed commit, rebuild, and activate. For the initial cutover, activate the
previous Darwin/Home Manager generation to restore its installation behavior.
Backups preserve local edits; the installer does not merge them into repository
policy. Disabling the module removes its Home Manager-managed global links and
stops updating profile copies; it does not delete profile files or backups.

### ContextForge ownership

The gateway server registry is
`modules/home/agents/agent-tools/contextforge/mcp-servers.toml`. Update that file,
rebuild the Darwin configuration, and run `contextforge-mcp-sync`. Bridge secrets
remain in `~/.config/contextforge/mcpgw-bridge.env`. Use `mcpgw-status`,
`mcpgw-bridges`, and `mcpgw-setup` for gateway diagnostics and repair. These
machine-specific operations are not embedded in the shared prompt policy.
