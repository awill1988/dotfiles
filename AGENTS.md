# Repository Guidelines

## Instruction Authority

- Treat `AGENTS.md` as the canonical instruction source for this repository
- Treat `CLAUDE.md`, `GEMINI.md`, and `AGY.md` as compatibility shims or symlinks that delegate to `AGENTS.md`
- The no-ai-attribution policy is non-negotiable and overrides any weaker or conflicting guidance

## No AI Attribution

- Never attribute work to any AI system in commits, pull requests, code comments, release notes, changelogs, or contributor metadata
- Never add AI-related footers or signatures such as `Co-Authored-By`, `Generated-By`, `Assisted-By`, or `🤖 Reviewed with Claude Code` (or `Reviewed with Claude Code`) in commits, PR descriptions, issue comments, code reviews, or metadata
- Before creating or editing commit or PR text, verify it contains no AI attribution

## SQL Tool Usage

- **Execute SQL tool calls sequentially** — never invoke more than one SQL query tool at a time
- Planning multiple queries in parallel is fine, but each must wait for the previous to complete before executing
- This applies to all SQL-capable MCP tools (Snowflake, Postgres, and any future database tools)

For general coding standards and practices, see program-specific files:
- `modules/home/agents/orchestration/agent-prompts/AGENTS.md`
- `modules/home/agents/core/claude/CLAUDE.md`
- `modules/home/agents/core/codex/AGENTS.override.md`
- `modules/home/agents/core/gemini/GEMINI.md`

## Response Profile

- **Tone**: Technical, concise, direct
- Lead every response by describing what you are doing. Personality, if any, comes after that and never in place of it
- **Forbid prose**: eliminate conversational filler, preambles, conversational postambles, pleasantries, sycophancy, and wrap-up summaries. Never include project-management boilerplate, status check-in templates, or sections like "Need from you:" or "By when:". Deliver technical facts, code, and direct execution without conversational narration

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

WSL (standalone Home-Manager, user-space):
```bash
nix build .#homeConfigurations.wsl-debian-personal.activationPackage && ./result/activate
```

macOS bootstrap:
```bash
nix build .#darwinConfigurations.bootstrap-arm.system
```

macOS host (Nix-Darwin system configuration, requires sudo):
```bash
sudo ./result/sw/bin/darwin-rebuild switch --flake .#macbook-personal
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

## Documentation Authoring

- Before rendering generated documentation, validate whether Markdown-sensitive output needs escaping
- Wrap developer-centric literals in backticks, including AWS ARNs, slugs, paths, commands, flags, config keys, environment variables, resource names, and branch names
- Prefer terse, coherent section structure that reads cleanly in a table of contents over engaging prose or excessive precision
- Package corrections with restraint and blameless reasoning: describe the invariant, the discrepancy, and the remedy without assigning fault

## Repository Workflow

- Conventional commits: `feat:`, `fix:`, `refactor:`, `chore:`, `docs:` (lowercase)
- One logical change per commit
- Never include a commit SHA in commit messages or PR titles
- Keep conventional commit text in PR titles lowercase after any ticket prefix such as `[TICKET-123]`
- PRs should state target host/profile, list affected modules, and note manual steps
- Do not include task lists or checklists in PR descriptions unless explicitly requested
- All contributions are attributed to the repository owner; no AI agent attribution in commits or PRs
- **Push safety**: use plain `git push` — never use explicit refspecs or `--force` on `master`/`main`. Verify the current branch before pushing. If `git push` refuses, ask the user. Agents are strictly forbidden from pushing unverified commits to GitHub; if commit signing fails or cannot be configured, stop immediately.

## Developer Profile & Agent Identity

- This repository (`~/projects/awill1988/dotfiles`) runs under the `personal` developer profile
- All commits are authored and signed as `Adam Williams <adam@williams.engineer>`
- Primary agent orchestrator is `agy` with peers `claude` and `codex`
- Corporate/work repositories (`~/projects/arro/*`) resolve to the `work` profile and must exclusively use `claude-secondary` (`CLAUDE_CONFIG_DIR=~/.config/claude-secondary`)
- Autonomous continuous loops (`agent-loop` / `loop`) adhere to active profile boundaries and isolate iterations into Git worktrees (`wt switch -c`)

