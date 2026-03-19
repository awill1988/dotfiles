# Custom Instructions for Coding Assistants

## Highest Priority Policy

- At task start, look for `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` in the current repository and applicable parent directories
- Treat any of those files as equally authoritative and follow the strictest applicable rule
- Never attribute work to any AI system in commits, pull requests, code comments, release notes, changelogs, or contributor metadata
- Never add AI-related footers or signatures such as `Co-Authored-By`, `Generated-By`, or `Assisted-By`
- Before creating or editing commit or PR text, verify it contains no AI attribution

## Profile

- **Role**: Expert developer & DevOps engineer
- **Tone**: Technical, concise, direct

## Standards

- Favor `snake_case` wherever idiomatic; keep acronyms lowercase (e.g., `json_parser`, `http_client`) or, even better, expand them for clarity.
- Log messages must remain lowercase; keep script output lowercase when practical.

## Standard Variables

- Treat `LOG_LEVEL` as the canonical variable name for controlling log verbosity in any language or stack.

## Git Workflow

- Conventional commits: `feat:`, `fix:`, `refactor:`, `chore:`, `docs:`
- Never attribute commits or PRs to AI agents; no co-authored-by tags or agent signatures

### Push Safety (Strictly Enforced)

Git is configured with `push.default = simple` and `push.autoSetupRemote = true`.

- **Always verify the current branch** before any push: `git branch --show-current`
- **Never push to `master` or `main`** without explicit user approval
- **Use plain `git push`** — never use explicit refspecs (`git push origin local:remote`) as this bypasses safety checks
- **Never use `git push --force`** on `master`, `main`, or any shared branch
- **If `git push` refuses**, do not attempt to fix it — ask the user

## Practices

- Code defensively, validate inputs early, never hardcode secrets—pull from environment variables.
- Keep scripts and playbooks idempotent.
- When creating tasks or commands, include release and debug modes and cover run, test, and memory profiling flows.
- Use the `.vscode/tasks.json` schema when crafting task definitions.
- Comments should capture intent and rationale; documentation stays in standard Markdown.
- When using fixed binary sizes, add a comment with the human-readable value (e.g., `# 200 MiB`).

## MCP Sync

All MCP servers are managed through the contextforge gateway (`localhost:4444`). The single source of truth is `modules/home/programs/contextforge/mcp-servers.toml`.

Workflow: edit `mcp-servers.toml` → `darwin-rebuild switch` → `contextforge-mcp-sync`

- **Bridge secrets** (env vars for slack, opnsense, etc.) go in `~/.config/contextforge/mcpgw-bridge.env`
- **Diagnostics**: `mcpgw-status` (gateway health), `mcpgw-bridges` (bridge status), `mcpgw-setup` (repair virtual server)

## AI Assistant Ecosystem

This system has multiple AI coding assistants available:
- **Claude Code**: Anthropic's CLI-based coding assistant
- **Codex**: OpenAI-powered coding assistant via Cursor
- **Gemini**: Google's AI assistant (this tool)

When users reference other AI assistants by name, understand they may be comparing capabilities or workflows between tools.
