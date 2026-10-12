# Blizzard

Blizzard is a native macOS SwiftUI menu bar app that controls **Bose QuietComfort Ultra Headphones (1st Gen, 2023, codename
lonestarr, Bluetooth PID 0x4066)**. It wraps the bosectl C++ BMAP library through a Blizzard-owned C shim,
and supplies its own Swift IOBluetooth RFCOMM transport.

Status: **pre-alpha / planning.** No code exists yet. Start at the first unticked task in `docs/PLAN.md`.

## Stack

- Swift 6 language mode with complete strict concurrency, SwiftUI `MenuBarExtra(.window)`, Swift Testing, Xcode 26, macOS 26 SDK.
- C++17 shim (`Sources/BMAPShim`) over bosectl's header-only C++ (`Vendor/bosectl`, git submodule at `70570b2` = v0.5.0).
  Swift sees only the plain C header `Sources/BMAPShim/include/bmap_shim.h`. C++ interop mode is not used (ADR-0002).
- IOBluetooth for Bluetooth Classic RFCOMM, channel 2 (ADR-0003).
- Distribution: Developer ID with notarisation. Sparkle 2 comes later (ADR-0006).

## Repo map

- `App/`: SwiftUI app target (views, `DeviceStore`, Info.plist, entitlements). Has its own AGENTS.md.
- `Sources/BMAPShim/`: C++ façade, allowlist, lonestarr config, gen-1 parsers. Has its own AGENTS.md.
- `Sources/RFCOMMTransport/`: IOBluetooth link, `BMAPThread`, discovery. Has its own AGENTS.md.
- `Sources/BlizzardCore/`: `DeviceSession` actor, models, errors, reconnect policy. Has its own AGENTS.md.
- `Sources/BlizzardProbe/`: `blizzard-probe`, a developer CLI for read-only GET sweeps and capture replay.
- `Tests/`: Swift Testing suites (shim tests go through the C API), plus `Tests/Fuzz/` (M4).
- `Fixtures/lonestarr/<fw>/`: scrubbed captured frames plus expected parses. Has its own AGENTS.md.
- `Vendor/bosectl/`: upstream submodule, **read-only**. See `Vendor/AGENTS.md`.
- `docs/`: SPEC, ARCHITECTURE, PLAN, PROTOCOL, SECURITY, plus `adr/`.
- `.claude/`: Claude Code settings (deny rules) and skills.

## Commands (planned: none of these work until PLAN T001-T005 and T029 are done)

```sh
git submodule update --init --recursive        # fetch Vendor/bosectl at the pinned commit
swift build                                    # package targets (shim, transport, core, probe)
swift test                                     # all unit tests; no hardware needed
cmake -S Vendor/bosectl/cpp -B .build/bosectl && cmake --build .build/bosectl && ctest --test-dir .build/bosectl
xcodebuild -project Blizzard.xcodeproj -scheme Blizzard -destination 'platform=macOS' build test
swift run blizzard-probe --read 0.5            # needs a paired headset; GET only
swift format lint --recursive Sources Tests App
```

Always build bosectl **out of tree** (`-B .build/...`), so the submodule stays clean.

## Rules that prevent real mistakes

IMPORTANT: Never send a BMAP packet to real headphones unless docs/PROTOCOL.md allows that exact (block, function, operator) for gen 1 and the shim allowlist permits it. Never use operator SET (0), and never touch blocks 3, 8, 18 or 20.

- **Wrap, don't port.** Protocol logic comes from bosectl. Gen-1 differences go in `Sources/BMAPShim/lonestarr_config.hpp`
  and `parsers_gen1.hpp`, never in a Swift re-implementation.
- **Never edit `Vendor/bosectl/`.** Fix it upstream, or bump it with `/bump-bosectl` (see `Vendor/AGENTS.md`).
- **No C++ exception may reach Swift.** Every `extern "C"` function catches `bmap::busy_error` before `connect_error`
  (its base), then the other `bmap::*_error` types, then `std::exception`, then `...`. Each one returns a `blz_status`.
- **IOBluetooth stays on `BMAPThread`.** Import it only in `Sources/RFCOMMTransport/`. Never call it from a Swift
  `async` context or `Task`: that times out with `-536870212`. Never block the main thread on Bluetooth.
- **The headset is untrusted input.** Bounds-check every length and offset, and cap buffers (64 KiB, 5 s drain).
- **Read back after every write**, and show the device's value, not the request.
- **Unverified means disabled.** A gen-1 address stays `nullopt` in the config, and absent from the allowlist, until
  `/verify-bmap-feature` records a fixture. Gen-2 evidence does not count.
- **No network code** (no `URLSession`/`Network.framework`/analytics) and no network entitlement. Sparkle is a future
  exception that needs an ADR first.
- **No secrets** in the repo or in output: `.env*`, `secrets/**`, `*.p12`, `*.p8`, signing or Sparkle keys.
  Scrub MAC addresses and serials from fixtures and logs (`os_log` `.private`).
- **Pin exactly**: the submodule commit, exact SwiftPM versions, and CI action versions.
- Do not weaken or delete a test to get green. Fix the code or ask.
- Full rule list with enforcement: `docs/SECURITY.md` §Rules for coding agents.

## Working agreement

- **Before starting:** read the task in `docs/PLAN.md` and the SPEC requirement it cites.
- **When you finish a task:** tick it in `docs/PLAN.md` in the same commit, with the date, the commit hash and evidence. Add any work you
  discovered as new task IDs. Never delete history.
- **When you make a decision:** for any decision a future contributor could make differently (dependency, threading,
  protocol policy, entitlement, distribution), write `docs/adr/NNNN-title.md` with the next number. Never edit an
  accepted ADR's Decision; supersede it with a new ADR instead.
- **When protocol knowledge changes:** update `docs/PROTOCOL.md` in the same change.
- **Show evidence, don't assert.** Paste the command you ran and its output.
- **Definition of done:** `swift build` + `swift test` are green (plus `xcodebuild test` once the app target exists).
  No new warnings. Fixtures and tests exist for any new parser or write. PLAN, PROTOCOL and ADRs are updated. Nothing changed in `Vendor/bosectl/`.
- **Spelling:** Australian/British in prose is fine. Use Apple's API spellings in code.
- **Per-directory AGENTS.md files** add to these rules; where one says "overrides", it wins inside that directory.

## Where to look

- What to build and how it is accepted: `docs/SPEC.md` (FR-### requirements, milestones M0-M4).
- How it fits together (layers, threading, data flow, errors): `docs/ARCHITECTURE.md`.
- Tasks and status: `docs/PLAN.md`.
- Gen-1 address table, statuses and sources: `docs/PROTOCOL.md`.
- Disclosure policy, threat model, agent rules: `docs/SECURITY.md`.
- Decisions: `docs/adr/` (0001 ADR process, 0002 C shim, 0003 RFCOMM transport, 0004 allowlist, 0005 AGENTS.md,
  0006 distribution).
- Upstream library: `Vendor/bosectl/docs/architecture.md`, `Vendor/bosectl/NOTES.md`.
