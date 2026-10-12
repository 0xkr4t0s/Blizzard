# 1. Record architecture decisions

- Status: Accepted
- Date: 2026-10-12

## Context

Blizzard is built largely by coding agents across many sessions. Agents lose context between sessions and,
left alone, re-decide settled questions or quietly reverse them. The repo is also a portfolio piece, so readers
should be able to see *why* it is built this way, not only *what* it does.

## Decision

We record architecturally significant decisions as short ADRs in `docs/adr/`. The format follows Michael Nygard's
"Documenting Architecture Decisions" (2011):

- Sections are Title, Status, Date, Context, Decision, Consequences, plus "Alternatives" where useful.
- Each ADR fits on about one page, under 60 lines.
- Files are named `NNNN-short-title.md` with 4-digit numbers, assigned sequentially and never reused.
- Status is one of `Proposed`, `Accepted`, `Deprecated` or `Superseded by ADR-NNNN`.
- An accepted ADR's Decision is never edited. To change it, write a new ADR that says "Supersedes ADR-NNNN", and set
  the old one's status. Dated "Notes" (such as spike results) may be appended to an accepted ADR without changing its decision.
- Agents write an ADR whenever they make a decision that a future contributor could reasonably make differently.
  Examples: a dependency, a threading model, a protocol policy, a distribution channel, or a security rule change.

Source: [Nygard 2011](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions).

## Consequences

- `AGENTS.md` points here and tells agents to add an ADR for new decisions. This rule is convention-only plus review.
- Some duplication with ARCHITECTURE.md is expected. ARCHITECTURE.md describes the current design; ADRs keep the reasoning and history.
- A small writing cost on every significant change.
