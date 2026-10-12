# Blizzard: plan

Requirements are in `docs/SPEC.md`, design in `docs/ARCHITECTURE.md`, and protocol status in `docs/PROTOCOL.md`.

## How to update this file

- Tick a task **in the same commit** that completes it, and append the date and short hash:
  `- [x] T009 … — 2026-10-20 abc1234`.
- Paste evidence (command and result, or the fixture path) on an indented line under the task. Spike tasks
  always record their outcome, even a failure, plus the ADR/ARCHITECTURE section they updated.
- Add discovered work as a new task using the **next free ID in that milestone's range** (M0 T001-T019,
  M1 T020-T039, M2 T040-T049, M3 T050-T069, M4 T070-T099). Never reuse or renumber an ID.
- Never delete history. A dropped task becomes `- [~] T0xx … (dropped: reason)`.
- If scope changes, edit SPEC.md first, then this file.
- When a milestone checkpoint passes, move the whole milestone block under **Done** at the bottom.
- `[P]` = can run in parallel with its neighbours. `[HW]` = needs the real headset. `[GATE]` = needs a verified
  PROTOCOL.md entry first.

## M0: tooling and feasibility spike

- [ ] T001 Create the SwiftPM skeleton in Swift 6 mode with targets BMAPShim, RFCOMMTransport, BlizzardCore and BlizzardProbe
      plus test targets (`Package.swift`, `Sources/*`, `Tests/*`).
- [x] T002 [P] Add `.gitignore` (`.build/`, `.env*`, `secrets/`, `*.p12`, `*.p8`, `*.pklg`, `*.btsnoop`, `*.log`) and an MIT `LICENSE`. — 2026-10-12
      Evidence: `git status --ignored` lists `.DS_Store` files as ignored (`!!`); LICENSE is MIT, © 2026 0xkr4t0s.
- [x] T003 Add the submodule `Vendor/bosectl` → https://github.com/aaronsb/bosectl at `70570b29c1d3c9ba775b08a29eaea72385de27b5`
      (v0.5.0). Check: `git -C Vendor/bosectl rev-parse HEAD`. — 2026-10-12
      Evidence: `git -C Vendor/bosectl rev-parse HEAD` → `70570b29c1d3c9ba775b08a29eaea72385de27b5`; `git -C Vendor/bosectl status --short` → empty.
- [ ] T004 Build and run upstream C++ tests out-of-tree on macOS (`cmake -S Vendor/bosectl/cpp -B .build/bosectl &&
      cmake --build .build/bosectl && ctest --test-dir .build/bosectl`). The submodule must stay clean (`git -C Vendor/bosectl status`).
- [ ] T005 BMAPShim compiles the vendored headers (no vendored `.cpp`). `include/bmap_shim.h` exposes `blz_abi_version()`,
      and a Swift test calls it (`Sources/BMAPShim/`, `Tests/BMAPShimTests/`).
- [ ] T006 Allowlist and deny-list with profiles APP, PROBE and REPLAY (`Sources/BMAPShim/allowlist.{hpp,cpp}`). There is one test per
      deny-list rule per profile (`Tests/BMAPShimTests/AllowlistTests.swift`). This task blocks T009 and everything that touches hardware.
- [ ] T007 `CallbackTransport` and an exception-safe façade skeleton (`Sources/BMAPShim/callback_transport.hpp`,
      `facade.cpp`). Test that a throwing or garbage link returns a status and never crashes (`Tests/BMAPShimTests/ExceptionSafetyTests.swift`).
- [ ] T008 [HW] Spike: open RFCOMM channel 2 from `BMAPThread` with its own run loop (Plan A). If it fails, try Plan B
      (main run loop + semaphore). Record the result in ADR-0003 and ARCHITECTURE §4 (`Sources/RFCOMMTransport/`).
- [ ] T009 [HW] Spike: GET [0.1], then GET [0.5], on the real headset through the shim. Save
      `Fixtures/lonestarr/<fw>/0.5-firmware.{hex,json}`.
- [ ] T010 [HW] [P] Spike: confirm `productID() == 0x4066` and the GET [0.3] reply. Check whether SDP returns a BMAP UUID record and
      which channel it gives, and how long SDP takes.
- [ ] T011 [HW] Spike: what happens when the Bose app on a phone holds the headset? Does a Mac client get
      refused, and with what error? Does holding RFCOMM from the Mac block the phone? Resolve SPEC NFR-003.
- [ ] T012 [HW] Spike: measure the refuse-after-close window (about 1 s per airvzxf), and whether `performSDPQuery` after a reconnect
      completes on the current macOS (bug reported on 15.5). Tune ARCHITECTURE §8.
- [ ] T013 [HW] Spike: a Developer-ID-signed build with Hardened Runtime and App Sandbox, using
      `com.apple.security.device.bluetooth` and `NSBluetoothAlwaysUsageDescription`, opens RFCOMM. Note when the TCC prompt appears
      and whether a CLI (`blizzard-probe`) gets Bluetooth access. Record in ADR-0006.
- [ ] T014 `blizzard-probe` with `--read <b.f>`, `--sweep` (PROBE profile, GET only), `--diff <before> <after>` and `--replay`
      (REPLAY profile, see `/verify-bmap-feature`). Output is scrubbed JSON (`Sources/BlizzardProbe/`).
- [ ] T015 [HW] Run the first full sweep, commit it scrubbed under `Fixtures/lonestarr/<fw>/sweeps/`, and fill the PROTOCOL.md
      "Blizzard verified" column for every GET that answered.
- [ ] T016 [P] CI on `macos-26` (`.github/workflows/ci.yml`): `swift build`, `swift test`, bosectl `ctest`, and grep checks
      (`IOBluetooth` imported only under `Sources/RFCOMMTransport/`, and no `URLSession`/`Network`/`NWConnection` anywhere).
- [ ] T017 [P] Enable GitHub private vulnerability reporting in the repo settings, as SECURITY.md promises.

**Checkpoint M0:** T009 shows a real firmware string through Swift → shim → bosectl → Swift, and the allowlist tests pass.
ADR-0003 and ADR-0006 record the spike outcomes. If T008 Plan A and Plan B both fail, stop and revisit ADR-0003 (BLE fallback).

## M1: connect and read-only status

- [ ] T020 `blizzard::qc_ultra_gen1()` config, with only verified addresses non-null (`Sources/BMAPShim/lonestarr_config.hpp`), plus
      a test that every non-null address has a fixture (`Tests/BMAPShimTests/ConfigTests.swift`).
- [ ] T021 Bounds-checked gen-1 parsers for battery, firmware, name, mode index and mode name (`Sources/BMAPShim/parsers_gen1.hpp`).
      Tests cover the fixtures plus truncated, oversize and concatenated frames (`Tests/BMAPShimTests/ParserTests.swift`).
- [ ] T022 Façade reads: `blz_init`, `blz_read_firmware`, `blz_read_battery`, `blz_read_mode_index` and `blz_read_mode_name`
      (`Sources/BMAPShim/facade.cpp`).
- [ ] T023 `IOBluetoothLink`: the full connect sequence and `sendRecv` timings from ARCHITECTURE §7, the drain caps, close handling and the
      DenyList second check (`Sources/RFCOMMTransport/IOBluetoothLink.swift`, `DenyList.swift`).
- [ ] T024 `BMAPThread` job FIFO with no re-entrancy, a debug assertion and tests (`Sources/RFCOMMTransport/BMAPThread.swift`).
- [ ] T025 Discovery and channel resolution: SDP 1.5 s → cache → 2 → 8/9 with GET [0.5] (`Sources/RFCOMMTransport/Discovery.swift`).
- [ ] T026 `DeviceSession` actor, `ShimBridge` and `BlizzardError` mapping per ARCHITECTURE §6 (`Sources/BlizzardCore/`).
- [ ] T027 `ReconnectPolicy` state machine and connect/disconnect notifications, with pure unit tests
      (`Sources/BlizzardCore/ReconnectPolicy.swift`, `Tests/BlizzardCoreTests/ReconnectPolicyTests.swift`).
- [ ] T028 `ReplayLink`, `SimLink` and a session replay suite (`Tests/BlizzardCoreTests/ReplayTests.swift`).
- [ ] T029 Xcode app target: `MenuBarExtra(.window)`, `LSUIElement`, `NSBluetoothAlwaysUsageDescription` and minimal entitlements
      (`Blizzard.xcodeproj`, `App/Info.plist`, `App/Blizzard.entitlements`).
- [ ] T030 `DeviceStore` (`@MainActor @Observable`): refresh on panel open, poll every ≥ 5 min while closed (`App/DeviceStore.swift`).
- [ ] T031 Read-only panel (battery, firmware, name, current mode) and menu bar icon states (`App/Views/`).
- [ ] T032 Busy and error UX per FR-017 and the PROTOCOL.md error table (`App/Views/StatusBanner.swift`).
- [ ] T033 [HW] M1 end-to-end run (SPEC §End-to-end verification). Paste the scrubbed diagnostics here.

**Checkpoint M1:** the M1 acceptance criteria in SPEC pass on hardware, and a subagent review of the diff against this file finds no gaps.

## M2: mode switching and self-voice

- [ ] T040 [HW] Verify the gen-1 mode table with GET [31.6] for idx 0-9, plus [31.2] and [31.11]. Record the preset count and first user slot
      in PROTOCOL.md.
- [ ] T041 APP allowlist rule for START [31.3]: len 2, idx 0-9, prompt 0/1. Add tests for out-of-range values.
- [ ] T042 `blz_set_mode` with RESULT/PROCESSING handling and a GET read-back. Replay tests include a PROCESSING reply.
- [ ] T043 [HW] `/verify-bmap-feature` for SETGET [1.11] on our unit. Commit the fixture and update PROTOCOL.md.
- [ ] T044 [GATE T043] `blz_set_self_voice` with read-back, an APP allowlist rule (len 2, persist=1, level 0-3) and tests.
- [ ] T045 Mode picker with a "play voice prompt" toggle, plus a self-voice control (`App/Views/ModePicker.swift`, `SelfVoiceControl.swift`).
- [ ] T046 [HW] M2 end-to-end run.

**Checkpoint M2:** every listed mode switches and reads back on hardware, and self-voice round-trips.

## M3: verified gen-1 extras (each implementation task is gated on its verify task)

- [ ] T050 [HW] Verify [1.7] EQ: read layout, and whether SETGET is accepted without auth (SPEC FR-031).
- [ ] T051 [GATE T050] EQ support in the shim, the allowlist and the UI.
- [ ] T052 [HW] Verify the [31.6] STATUS and SETGET lengths, the editable flag and the spatial byte on a user slot (FR-032).
- [ ] T053 [GATE T052] Custom mode editing (editable slots only), using a Blizzard parser or a reviewed upstream parser.
- [ ] T054 [HW] Decode the [1.4] auto-off read `a0 00 05` and capture the Bose app's write (FR-033).
- [ ] T055 [GATE T054] Auto-off control.
- [ ] T056 [HW] Verify the SETGET [1.2] rename on gen 1 (FR-034).
- [ ] T057 [GATE T056] Rename UI with a 31-byte UTF-8 limit.
- [ ] T058 [HW] Resolve the [1.5] byte order, whether [31.10] exists, and per-mode immersive audio (FR-035).
- [ ] T059 [GATE T058] Read-only ANC level and immersive display.
- [ ] T060 Upstream PR to aaronsb/bosectl: a `qc_ultra` config, fixtures and a catalog key for 0x4066, in all three languages
      per its "Adding a New Device" steps.

**Checkpoint M3:** every enabled M3 control has a Blizzard-verified PROTOCOL.md row and a fixture test.

## M4: polish and distribution

- [ ] T070 Launch at login via `SMAppService.mainApp`, handling `.requiresApproval` (`App/LoginItem.swift`).
- [ ] T071 Liquid Glass on macOS 26 (`GlassEffectContainer`), light/dark, and the Reduce Transparency fallback.
- [ ] T072 Accessibility pass: VoiceOver labels and keyboard navigation (FR-044).
- [ ] T073 libFuzzer harness for `parsers_gen1.hpp` and the frame walker, plus a corpus from `Fixtures/` (`Tests/Fuzz/`).
- [ ] T074 "Copy diagnostics" with scrubbing tests (FR-045).
- [ ] T075 Investigate unsolicited STATUS (push updates for mode and battery) using bosectl's `parse_all_responses`.
- [ ] T076 Developer ID archive, notarise and staple with `scripts/release.sh` (see `/release`).
- [ ] T077 Write a new ADR for Sparkle 2 and its network exception, then integrate Sparkle (pinned SPM version, EdDSA,
      `SURequireSignedFeed`).
- [ ] T078 Homebrew cask in our own tap.
- [ ] T079 Expand the SECURITY.md threat model with fuzzing results (portfolio write-up).
- [ ] T080 Tag v0.1.0 and publish release notes.

**Checkpoint M4:** a notarised DMG installs cleanly on a fresh Mac account, and the SPEC M4 acceptance criteria pass.

## Done

(Completed milestones move here, with their checkpoint evidence.)
