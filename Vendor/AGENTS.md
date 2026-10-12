# Vendor/: third-party code (read-only)

This directory adds to the root AGENTS.md. It covers `Vendor/bosectl/` and `Vendor/patches/`.
These notes live here, not inside the submodule, because anything written inside `Vendor/bosectl/` would dirty it.

## Vendor/bosectl: do not edit

- It is a git submodule pinned to `70570b29c1d3c9ba775b08a29eaea72385de27b5` (tag v0.5.0, 2026-09-28) of
  https://github.com/aaronsb/bosectl. The licence is MIT, (c) 2026 Aaron Bockelie, so keep its LICENSE file and credit it in README.
- **Never edit, format or build inside it.** `.claude/settings.json` denies Edit/Write there, and CI fails if
  `git -C Vendor/bosectl status --porcelain` is non-empty. Build its tests out of tree:
  `cmake -S Vendor/bosectl/cpp -B .build/bosectl && cmake --build .build/bosectl && ctest --test-dir .build/bosectl`.
- **What we use:** C++ headers under `cpp/src/`, namely `protocol.h`, `device.h`, `devices.h`, `connection.h`, `catalog.h`,
  `errors.h`, and `transport.h` for the abstract `Transport` only.
- **What we don't use:** `transport.cpp` (its macOS branch throws), `discovery.cpp` (returns `nullopt` on Apple
  platforms), `bmap.h` / `connect()`, and the Python and Rust trees. The Python files are still the best reference for macOS behaviour:
  `python/pybmap/transport.py` (`MacOsRfcommTransport`) and `python/pybmap/discovery.py`.
- **Useful reading:** `docs/architecture.md` ("Adding a New Device"), `NOTES.md` (QCU2 reverse-engineering notes),
  `fixtures/`, `captures/`, `bmap-capture.py`.
- **State at the pin:**
  - lonestarr (0x4066) is in `catalog.h` with `config = nullptr`, so there is no gen-1 config upstream.
  - Open PR #43 fixes the QCU2 48-byte ModeConfig wind offset (byte 45 → 46) and is **not** in v0.5.0.
  - No PR mentions lonestarr.

## How to bump

Use `/bump-bosectl` (`.claude/skills/bump-bosectl/SKILL.md`). In short:
1. Read the upstream changelog and diff since the pin.
2. Move the submodule.
3. Run the upstream ctest plus our full `swift test`.
4. Review any changes to `device.h` / `connection.h` / `errors.h` against our shim.
5. Update this file, the pin in AGENTS.md / ARCHITECTURE.md / ADR-0002, and PLAN.

A bump is its own PR, never mixed with features.

## Vendor/patches (normally empty)

A local patch is a last resort, for an upstream fix we need before it merges. It requires:
- an ADR;
- a `NNNN-description.patch` file here, applied at build time to a copy, never to the submodule;
- a link to the upstream PR;
- deletion when we bump past the fix.

## Other dependencies

Sparkle 2 (M4) will be added through SwiftPM with an exact version, after its ADR. Nothing else is vendored.
