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
  - Sets `$DEVELOPER_PROFILE`, `$CLAUDE_CONFIG_DIR`, `$GEMINI_CONFIG_DIR`, `$CODEX_CONFIG_DIR`, `$AGY_CONFIG_DIR`, `$AWS_PROFILE`, `$AWS_REGION`, and Git author details dynamically on execution.
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
