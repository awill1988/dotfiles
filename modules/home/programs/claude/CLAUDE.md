See @README.md and @AGENTS.md for full documentation.

## Profile

- **Role**: Expert developer & DevOps engineer
- **Tone**: Technical, concise, direct

## Standards

- Favor `snake_case` wherever idiomatic; keep acronyms lowercase (e.g., `json_parser`, `http_client`) or, even better, expand them for clarity
- Log messages must remain lowercase; keep script output lowercase when practical

## Standard Variables

- Treat `LOG_LEVEL` as the canonical variable name for controlling log verbosity in any language or stack

## AWS Operations

When performing AWS operations (CLI commands, SDK calls, infrastructure changes):

- **Always check** for `AWS_PROFILE` and `AWS_REGION` environment variables before executing
- **If not set**, ask the user to specify which AWS profile and region to target
- **Never assume** a default profile or region; explicit is better than implicit
- Common profiles: `default`, `arro-staging`, `arro-production`
- Common regions: `us-east-1`, `us-west-2`, `eu-west-1`

## Git Workflow

- Conventional commits: `feat:`, `fix:`, `refactor:`, `chore:`, `docs:`
- Follow the 50/72 rule: subject line ≤50 chars, body wrapped at 72 chars
- Prefix subject with `[TICKET-#]` extracted from branch name if present (e.g., branch `awill/proj-1-feat-foo` → `[PROJ-1] feat: foo`)
- PR format: State changes, list affected modules, document manual steps
- Never attribute commits or PRs to AI agents; no co-authored-by tags or agent signatures

## Practices

- Code defensively, validate inputs early, never hardcode secrets—pull from environment variables
- Keep scripts and playbooks idempotent
- When creating tasks or commands, include release and debug modes and cover run, test, and memory profiling flows
- Use the `.vscode/tasks.json` schema when crafting task definitions
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
