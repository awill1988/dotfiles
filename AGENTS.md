# Repository Guidelines

## Project Structure & Module Organization
- `flake.nix` defines inputs, overlays, formatter, and the flake outputs for macOS, WSL, and NixOS builds; `flake.lock` pins versions.
- `home/` contains home-manager modules (config files, shells, terminal, git, gpg, packages).
- `system/` holds host and platform modules (common system config plus `system/darwin/` for macOS hosts).
- `modules/` exposes shared option sets such as `users.nix`; `overlays/` holds Nixpkgs overlays.
- `.editorconfig` captures formatting defaults; `result/` is the build artifact symlink produced by `nix build`.

## Build, Test, and Development Commands
- WSL: `nix build --extra-experimental-features nix-command --extra-experimental-features flakes .#homeConfigurations.debianWsl.activationPackage && ./result/activate` builds and activates the WSL home profile.
- macOS bootstrap: `nix build --extra-experimental-features nix-command --extra-experimental-features flakes .#darwinConfigurations.bootstrap-arm.system`.
- macOS host: `sudo ./result/sw/bin/darwin-rebuild switch --flake .#macbook-arm` applies the built system profile.
- Lint/format: `nix fmt` runs nixpkgs-fmt across Nix files; use `nix develop` to enter a shell with pinned toolchains if needed.
- Validation: `nix flake check` to evaluate flake correctness before pushing.

## Coding Style & Naming Conventions
- Prefer snake_case for identifiers and option names; keep acronyms lowercase or expanded for clarity.
- Indent Nix with two spaces; keep expressions compact and default to single-quoted strings where possible.
- Keep log and script output lower-case; gate verbosity with `LOG_LEVEL` when applicable.
- Do not hardcode secrets; prefer environment variables or GPG-backed inputs.

## Build & Toolchain Semantics
- Prefer defaults: avoid restating compilation flags or toolchain settings (any language) when the default matches; duplicated defaults are treated as a quality regression.

## Testing Guidelines
- Primary check is successful evaluation/build of flake targets (`nix flake check`, targeted `nix build` commands above).
- After building a home profile, run `./result/activate` and confirm no errors; for darwin, ensure `darwin-rebuild switch` completes cleanly.
- Name Nix test files or modules to reflect the host/target (e.g., `host-mac.nix`) and colocate related assets with their module.

## Commit & Pull Request Guidelines
- Follow conventional-style subjects seen in history (`feat: ...`, `fix: ...`, `refactor: ...`), keeping them lowercase and concise.
- One logical change per commit; include rationale in the body when behavior shifts.
- Pull requests should state the target host/profile, list affected modules or overlays, and note any manual steps (e.g., rerunning `./result/activate` or `darwin-rebuild switch`).

## Docs & Writing Quality
- Keep prose direct and operational; prefer imperative sentences for steps and configuration guidance.
