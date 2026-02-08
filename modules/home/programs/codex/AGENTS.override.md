# Custom Instructions for Coding Assistants

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
- **Claude Code**: Anthropic's CLI-based coding assistant (this tool)
- **Codex**: OpenAI-powered coding assistant via Cursor
- **Gemini**: Google's AI assistant

When users reference other AI assistants by name, understand they may be comparing capabilities or workflows between tools.
