# Repository Guidelines

For general coding standards and practices, see program-specific files:
- `modules/home/programs/claude/CLAUDE.md`
- `modules/home/programs/codex/AGENTS.override.md`
- `modules/home/programs/gemini/GEMINI.md`

## Project Structure

- `flake.nix` defines inputs, overlays, formatter, and flake outputs for macOS, WSL, and NixOS builds
- `home/` contains home-manager modules (config files, shells, terminal, git, gpg, packages)
  - `home/config/nvim/lua/ext/` holds neovim lua configuration
  - `home/config/nvim/lua/ext/keymaps.lua` centralizes all keybindings
- `system/` holds host and platform modules (`system/darwin/` for macOS hosts)
- `modules/` exposes shared option sets (`users.nix`) and program configurations
- `overlays/` holds Nixpkgs overlays
- `userinfo.nix` defines user configuration (hardcoded values to be customized after forking)

## Build Commands

WSL:
```bash
nix build .#homeConfigurations.debianWsl.activationPackage && ./result/activate
```

macOS bootstrap:
```bash
nix build .#darwinConfigurations.bootstrap-arm.system
```

macOS host:
```bash
./result/sw/bin/darwin-rebuild switch --flake .#macbook-arm
```

## Development Workflow

- Format: `nix fmt` runs nixpkgs-fmt across Nix files
- Validate: `nix flake check` before pushing
- Test: after building a home profile, run `./result/activate` and confirm no errors; for darwin, ensure `darwin-rebuild switch` completes cleanly

## Nix-Specific Conventions

- Indent with two spaces; prefer single-quoted strings
- Name modules to reflect the host/target (e.g., `host-mac.nix`)
- Prefer defaults: avoid restating compilation flags or toolchain settings when the default matches
- User configuration flows through environment variables via `user.nix`

## Repository Workflow

- Conventional commits: `feat:`, `fix:`, `refactor:`, `chore:`, `docs:` (lowercase)
- One logical change per commit
- PRs should state target host/profile, list affected modules, and note manual steps
- All contributions are attributed to the repository owner; no AI agent attribution in commits or PRs
- **Push safety**: use plain `git push` — never use explicit refspecs or `--force` on `master`/`main`. Verify the current branch before pushing. If `git push` refuses, ask the user.
