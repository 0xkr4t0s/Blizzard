# 5. AGENTS.md is canonical; CLAUDE.md files only import it

- Status: Accepted
- Date: 2026-10-12

## Context

The goal is "CLAUDE.md + an AGENTS.md symlink", so that Claude Code and other agents (Codex, Cursor, Gemini CLI and others) all read the
same instructions, including per-subsystem notes. Research found three problems with that plan:

- **Symlinks:**
  - Claude Code's Edit/Write tools refuse to write through a symlink.
  - On Windows, symlinks need Admin or Developer Mode, and Git checks them out as one-line text files unless `core.symlinks` is set.
  - Anthropic's docs recommend `@AGENTS.md` instead "if you or anyone who clones the repository works on Windows".
- **Nested files:** Claude Code reads AGENTS.md natively (v2.1.277+), but only when no CLAUDE.md / CLAUDE.local.md exists at or above
  the working directory. With a root CLAUDE.md, the default mode loads "CLAUDE.md files only", so nested `<dir>/AGENTS.md` files are
  ignored. A personal CLAUDE.local.md silently has the same effect.
- **Import vs instruction:** a CLAUDE.md that only says "read AGENTS.md" is unreliable. An `@AGENTS.md` import is deterministic and
  "never makes Claude read AGENTS.md twice".

Codex concatenates AGENTS.md files from the root down to cwd, and the agents.md spec says the closest file wins.

Sources: [Claude Code memory docs](https://code.claude.com/docs/en/memory), [agents.md](https://agents.md/),
[Codex AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

## Decision

- `AGENTS.md` is the canonical, tool-neutral instruction file at **every** level.
- Root `CLAUDE.md` contains `@AGENTS.md` plus a few Claude-only lines (skills, plan mode, settings).
- Each subsystem directory that has an `AGENTS.md` also has a one-line `CLAUDE.md` containing `@AGENTS.md`.
  Claude Code loads it on demand when it touches files there.
- No symlinks anywhere.
- Subsystem files state only what they add to or override in the root file, and name any override explicitly.
- Vendor notes live in `Vendor/AGENTS.md`, never inside the submodule.

## Consequences

- Works on every Claude Code version and mode and on Windows checkouts. Other agents see plain AGENTS.md files.
- Every new AGENTS.md needs its sibling CLAUDE.md. A missing sibling means Claude silently skips the notes. This is convention plus
  review; a CI check is cheap to add later.
- Root AGENTS.md stays under 150 lines (Anthropic's target is under 200), and big docs are pointed to rather than imported.
