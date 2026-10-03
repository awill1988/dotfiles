# ADR-0001: Generalized Repository Entrypoint for Agentic Workflows (`.agents/`)

- **Status**: Accepted
- **Date**: 2026-10-03
- **Deciders**: Adam Williams
- **Consulted**: Repository Guidelines (`AGENTS.md`), Antigravity Customization Guide (`agy-customizations`)

---

## Context and Problem Statement

Modern software engineering repositories interact with a heterogeneous set of AI coding agents (`agy`, `claude`, `codex`, `gemini`, `opencode`), autonomous feedback loops (`agent-loop`), and continuous integration runners. Each agent ecosystem introduces its own configuration formats, instruction files, permission rules, and telemetry behaviors.

Crucially, **agent CLI programs do not automatically execute entrypoint scripts**:
- CLI tools discover and parse instruction files (`*.md`) and workspace customization folders.
- Execution requires explicit invocation by human developers, git hooks, or CI/CD pipelines.

When designing repository automation, using a single file named `.agents` at the repository root creates an immediate collision with Antigravity (`agy`), which natively discovers `.agents/` as its workspace customization directory. Furthermore, executing nested scripts like `.agents/agents` introduces redundant stuttering.

A standardized, zero-dependency entrypoint structure is required that aligns with native agent discovery conventions while providing clean, dedicated commands for each agent CLI.

---

## Decision Drivers

- **Alignment with Native Agent Discovery**: Must coexist cleanly with tools like Antigravity (`agy`), which natively treats `.agents/` as the workspace directory for rules, skills, and hooks.
- **Dedicated, Clean Execution Surface**: Avoid awkward stuttering (`.agents/agents`) or file/directory naming conflicts (`.agents` vs `.agents/`). Provide intuitive `./.agents/{agent_name}` invocations.
- **Zero-Dependency Portability**: Must execute reliably on minimal containers, CI runners, Alpine (BusyBox `ash`), Debian (`dash`), NixOS, macOS, FreeBSD, and Windows Git Bash/MSYS2 without requiring Python or Node.js runtimes.
- **Strict POSIX Compliance**: Must avoid shell-specific extensions ("bashisms") across all entrypoint scripts.
- **Enforced Repository Invariants**: Guarantee canonical instruction authority (`AGENTS.md`), eliminate prohibited AI attribution, check commit signing, and guard branch push safety.
- **Telemetry and Privacy Suppression**: Ensure all agent executions enforce telemetry shutdown flags across all sub-processes.

---

## Analysis of Agent CLI Default Discovery Behaviors

| Agent Tool | Native Instruction Files | Native Config / Customization Directory | Default Discovery Behavior |
| :--- | :--- | :--- | :--- |
| **Antigravity (`agy`)** | `AGENTS.md`, `GEMINI.md` | **`.agents/`** (also `.agent/`, `_agents/`) | Discovers `.agents/rules/`, `.agents/skills/`, `.agents/hooks.json`, `.agents/mcp_config.json` automatically walking up from CWD to repo root. |
| **Claude Code (`claude`)** | `CLAUDE.md` | `~/.claude/`, `.claude/` | Looks only for `CLAUDE.md` and `.claude/`. Ignores `.agents/` unless symlinked or instructed via `CLAUDE.md`. |
| **OpenAI Codex (`codex`)** | `AGENTS.md`, `CODEX.md` | `~/.codex/` | Natively reads `AGENTS.md`. |
| **Gemini CLI** | `GEMINI.md`, `AGENTS.md` | `~/.gemini/config/`, `.agents/` | Shares Antigravity discovery engine for `AGENTS.md` and `.agents/`. |
| **OpenCode (`opencode`)** | `AGENTS.md`, `OPENCODE.md` | `.opencode/` | Natively reads `AGENTS.md`. |
| **Cursor IDE** | `AGENTS.md`, `.cursorrules`, `.cursor/rules/*.mdc` | `.cursor/` | Natively reads `AGENTS.md` and `.cursor/rules/`. |

---

## Decision Outcome

Adopt **`.agents/` as a first-class directory** at the repository root containing:
1. A shared, strict POSIX runtime library (`_common.sh`).
2. Dedicated per-agent executable entrypoints (`.agents/{agent_name}`).
3. Dedicated workflow and verification utilities (`.agents/check`, `.agents/init`, `.agents/context`, `.agents/loop`, `.agents/exec`).
4. Native Antigravity workspace customizations (`rules/`, `skills/`, `hooks/`).

### 1. File and Directory Topology

```
<repo-root>/
├── .agents/                    # First-class agent directory
│   ├── _common.sh              # Shared POSIX runtime helpers & telemetry guards
│   ├── agy                     # Executable launcher for Antigravity
│   ├── claude                  # Executable launcher for Claude Code
│   ├── codex                   # Executable launcher for OpenAI Codex
│   ├── gemini                  # Executable launcher for Gemini CLI
│   ├── opencode                # Executable launcher for OpenCode
│   ├── check                   # Verification utility (attribution, signing, branch)
│   ├── init                    # Bootstrapper (AGENTS.md, shims, config template)
│   ├── context                 # Structured repo context & tooling inspector
│   ├── loop                    # Continuous agent loop orchestrator
│   ├── exec                    # Guarded command execution runner
│   ├── config.env              # Optional repo-level agent environment overrides
│   ├── rules/                  # Antigravity project rules
│   └── skills/                 # Antigravity progressive skills
├── AGENTS.md                   # Canonical repository instruction authority
├── CLAUDE.md -> AGENTS.md      # Symlink compatibility shim
├── GEMINI.md -> AGENTS.md      # Symlink compatibility shim
├── AGY.md -> AGENTS.md         # Symlink compatibility shim
└── CODEX.md -> AGENTS.md       # Symlink compatibility shim
```

### 2. Shebang & Portability Specification

All scripts in `.agents/` use:

```sh
#!/usr/bin/env sh
```

- Adheres strictly to IEEE Std 1003.1 (POSIX shell).
- No bashisms (`[[ ... ]]`, arrays, `function` keyword, non-standard `echo` flags).
- Every script sources `.agents/_common.sh` using relative directory resolution (`$(cd "$(dirname "$0")" && pwd)`), making scripts location-independent.

### 3. Execution Model

Instead of routing through a single dispatcher file, developers and automation run dedicated entrypoints directly:

```bash
# Launch specific agents with telemetry shutdown & profile guards:
./.agents/agy
./.agents/claude "implement feature X"
./.agents/codex "refactor tests"

# Run repository invariant checks:
./.agents/check

# Initialize shims and structure:
./.agents/init

# Dump repository context:
./.agents/context

# Execute arbitrary commands inside guarded environment:
./.agents/exec make test
```

### 4. Telemetry and Privacy Guarantees

All entrypoints in `.agents/` unconditionally export telemetry shutdown variables before running sub-processes:

```sh
DO_NOT_TRACK="1"
DISABLE_TELEMETRY="1"
CODEX_DISABLE_TELEMETRY="1"
AGY_TELEMETRY_ENABLED="false"
ANTIGRAVITY_TELEMETRY_ENABLED="false"
OPENCODE_TELEMETRY_ENABLED="false"
OTEL_SDK_DISABLED="true"
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
DISABLE_NON_ESSENTIAL_MODEL_CALLS="1"
DISABLE_AUTOUPDATER="1"
DISABLE_GROWTHBOOK="1"
DISABLE_ERROR_REPORTING="1"
```

---

## Consequences

### Positive

- **Natural Synergy**: Fully harmonizes with Antigravity (`agy`), which already uses `.agents/` for workspace discovery.
- **No Stuttering or Collisions**: Eliminates awkward `.agents/agents` naming and avoids file/directory collisions.
- **Ergonomic Direct Invocations**: Running `./.agents/claude` or `./.agents/agy` is shorter, clearer, and more direct than `./.agents run claude`.
- **Modularity & Maintainability**: Each agent script is tiny (~6 lines) and delegates to `_common.sh`, making maintenance centralized.
- **Portability**: 100% pure POSIX shell across all scripts; executes identically on macOS, NixOS, Alpine, Linux, and Windows Git Bash/WSL.

### Negative / Trade-offs

- Requires managing multiple small executable files in `.agents/` rather than a single monolithic script; mitigated by shared logic in `_common.sh`.
