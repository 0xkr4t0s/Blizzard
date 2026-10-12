@AGENTS.md

## Claude Code specifics

- Each subsystem directory has an `AGENTS.md` plus a one-line `CLAUDE.md` that imports it. If you add an
  `AGENTS.md`, add the sibling `CLAUDE.md` (`@AGENTS.md`) too, or Claude will not load it (ADR-0005). Never use symlinks.
- Skills are user-invoked only, because each one has side effects. Suggest them when relevant:
  - `/verify-bmap-feature`: confirm a gen-1 address on hardware before implementing it.
  - `/bump-bosectl`: move the pinned submodule.
  - `/release`: sign, notarise, staple and publish.
- Use plan mode before changing the allowlist, the lonestarr config, the C API, the transport, threading,
  or entitlements. Present the plan and wait for approval.
- `.claude/settings.json` denies reading secrets and editing `Vendor/bosectl/**`. If a deny blocks you, stop and
  ask. Do not work around it with Bash.
- Before ticking a milestone checkpoint, run a subagent review of the diff against `docs/PLAN.md` and the SPEC
  acceptance criteria. Report only gaps that affect correctness or stated requirements.
- When compacting, keep the current PLAN task ID, the list of modified files, and the exact test commands.
