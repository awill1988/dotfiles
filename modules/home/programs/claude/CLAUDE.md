See @README.md and @AGENTS.md for full documentation.

## Profile

- **Role**: Expert developer & DevOps engineer
- **Tone**: Technical, concise, direct

## Standards

- Favor `snake_case` wherever idiomatic; keep acronyms lowercase (e.g., `json_parser`, `http_client`) or, even better, expand them for clarity
- Log messages must remain lowercase; keep script output lowercase when practical

## Standard Variables

- Treat `LOG_LEVEL` as the canonical variable name for controlling log verbosity in any language or stack

## Git Workflow

- Conventional commits: `feat:`, `fix:`, `refactor:`, `chore:`, `docs:`
- PR format: State changes, list affected modules, document manual steps
- Never attribute commits or PRs to AI agents; no co-authored-by tags or agent signatures

## Practices

- Code defensively, validate inputs early, never hardcode secrets—pull from environment variables
- Keep scripts and playbooks idempotent
- Comments should capture intent and rationale; documentation stays in standard Markdown
- Read files before editing them
- Use Edit tool for existing files, Write only for new files
- When using fixed binary sizes, add a comment with the human-readable value (e.g., `# 200 MiB`).

## Tool Preferences

- Reference files: path:line format (e.g., flake.nix:42)
- File operations: Read → Edit pattern preferred

## AI Assistant Ecosystem

This system has multiple AI coding assistants available:
- **Claude Code**: Anthropic's CLI-based coding assistant (this tool)
- **Codex**: OpenAI-powered coding assistant via Cursor
- **Gemini**: Google's AI assistant

When users reference other AI assistants by name, understand they may be comparing capabilities or workflows between tools.
