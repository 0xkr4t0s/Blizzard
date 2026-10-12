# Blizzard: specification

Status: draft · 2026-10-12 · Owner: repo author.
Related docs: protocol facts in `docs/PROTOCOL.md`, design in `docs/ARCHITECTURE.md`, tasks in `docs/PLAN.md`,
safety rules in `docs/SECURITY.md`. Requirement IDs are stable. Never renumber them; mark a dropped one `(withdrawn)`.

## Problem

Bose's companion app only runs on phones. Owners of the **QuietComfort Ultra Headphones (1st Gen, 2023,
codename lonestarr, PID 0x4066)** have no way to switch modes or check battery from a Mac.
The open-source **bosectl** library (MIT) speaks Bose's BMAP protocol, but it has two gaps:

- Its C++ and Rust transports are Linux/BlueZ only. On macOS, only the Python library works.
- lonestarr is in its catalog with `config = None`, so the gen-1 address map is unproven.

## Goals

1. A native macOS menu bar app that shows status and switches modes on gen-1 headphones, with no phone needed.
2. Reuse bosectl's C++ codec, `DeviceConfig` and `BmapConnection` by wrapping them (ADR-0002). Do not port.
3. Make a safety-first protocol posture visible: a command allowlist, the device treated as untrusted
   input, and a documented verification method. This is a portfolio deliverable in its own right.
4. Contribute a verified `qc_ultra` (lonestarr) config and captures back to bosectl upstream.

## Non-goals (out of scope unless a new ADR says otherwise)

- Mac App Store distribution (ADR-0006). iOS/iPadOS. Windows/Linux.
- Supporting other Bose products, including QC Ultra 2nd Gen. It may work through upstream configs but is not tested.
- Anything that needs Bose cloud authentication: operator SET, block 18, and key or certificate work.
- Firmware updates, factory reset, ship mode, power off, pairing and paired-device management, multipoint routing.
- Media keys ([5.3] returns Busy on gen 1) and volume ([5.5]; macOS already does this).
- A BLE/CoreBluetooth transport. That is a documented fallback only (ADR-0003).
- Accounts, sync, telemetry, analytics, crash upload.

## Users

- **Primary:** the author, a gen-1 owner on a current Mac who wants one-click mode switching and battery level.
- **Secondary:** other gen-1 owners installing a notarised build or a Homebrew cask.
- **Tertiary:** reviewers and hiring managers reading the repo (docs, ADRs, tests and security posture are part of the product).

## Functional requirements

### M0: tooling and feasibility spike

- **FR-001** The build MUST compile bosectl's header-only C++ (`protocol.h`, `device.h`, `devices.h`,
  `connection.h`, `catalog.h`, `errors.h`) from `Vendor/bosectl` pinned at `70570b2` (v0.5.0) without modifying it.
- **FR-002** The system MUST open IOBluetooth RFCOMM channel 2 to a paired 0x4066 headset from Swift and
  complete GET [0.1] then GET [0.5].
- **FR-003** Every outbound BMAP packet MUST pass the shim allowlist and deny-list (`docs/SECURITY.md` §Rules)
  before it reaches the transport.
- **FR-004** No C++ exception MUST ever propagate into Swift. Every C entry point returns a status code.
- **FR-005** `blizzard-probe` MUST perform a read-only GET sweep of the allowlisted addresses and write
  scrubbed JSON (MACs and serials redacted) to `Fixtures/lonestarr/<fw>/sweeps/`.

### M1: connect and read-only status

- **FR-010** The system MUST find the headset among `IOBluetoothDevice.pairedDevices()` by `productID() == 0x4066`,
  preferring a device whose `isConnected()` is true.
- **FR-011** The system MUST resolve the BMAP channel in this order: SDP record for UUID
  `00000000-deca-fade-deca-deafdecacaff` (time-boxed to 1.5 s), then the cached channel, then 2, then 8 and 9.
  Each fallback MUST be confirmed with GET [0.5].
- **FR-012** The system MUST send GET [0.1] on every connect and discard the version payload.
- **FR-013** The system MUST show battery percentage from [2.2], plus remaining time when the minutes field is not 0xFFFF.
- **FR-014** The system MUST show firmware [0.5] and device name [1.2].
- **FR-015** The system MUST show the current mode index from [31.3] and its name from [31.6] (indices 0-9 only).
- **FR-016** The system MUST reconnect using the policy in ARCHITECTURE.md §Reconnect. It MUST wait at least 1 s after a close before reopening.
- **FR-017** If the channel is held by another client, the system MUST show a "busy" state with guidance and
  MUST NOT retry in a tight loop.
- **FR-018** The menu bar icon MUST reflect the state: disconnected, connecting, connected, busy or error.
- **FR-019** The system MUST refresh status when the panel opens, and poll at a low rate while it is closed.

### M2: mode switching and self-voice

- **FR-020** The system MUST list the available modes (indices 0-9 whose [31.6] name is not "None").
- **FR-021** The system MUST switch modes with START [31.3] `[idx, prompt]`, treat RESULT or PROCESSING as
  accepted, and confirm with a GET [31.3] read-back.
- **FR-022** The user MUST be able to choose whether a mode switch plays the headset's voice prompt (prompt byte 0/1).
- **FR-023** The system MUST set self-voice with SETGET [1.11] `[1, level]` (off/high/medium/low) and confirm
  the level from the STATUS reply, or from a GET read-back where that is verified.
- **FR-024** Mode changes made on the headset MUST appear in the UI on the next refresh.

### M3: verified gen-1 extras (each one is gated)

- **FR-030** No M3 feature MUST be enabled until `docs/PROTOCOL.md` marks its write Blizzard-verified,
  with a fixture captured on gen-1 hardware (`/verify-bmap-feature`).
- **FR-031** 3-band EQ, bass/mid/treble −10..+10, via [1.7].
  [NEEDS CLARIFICATION: does gen 1 accept SETGET on [1.7] without auth? Only the read is reported.]
- **FR-032** Create and edit custom modes in editable slots only, never presets, via SETGET [31.6].
  [NEEDS CLARIFICATION: gen-1 STATUS/SETGET lengths (47/39 like prince, or 48/40 like QCU2?), where the
  editable flag lives, and where user slots start.]
- **FR-033** Auto-off timer via [1.4]. [NEEDS CLARIFICATION: meaning of the gen-1 read `a0 00 05`.]
- **FR-034** Rename the headset via SETGET [1.2], at most 31 UTF-8 bytes. The write is UNVERIFIED on gen 1.
- **FR-035** Show the noise-cancelling level and immersive-audio setting of the current mode, read-only.
  [NEEDS CLARIFICATION: [1.5] byte order; whether [31.10] exists on gen 1.]

### M4: polish and distribution

- **FR-040** Launch at login via `SMAppService.mainApp`, including the `.requiresApproval` state.
- **FR-041** Light and dark appearance with semantic colours. Liquid Glass (`glassEffect`, `GlassEffectContainer`)
  on macOS 26 and a plain fallback elsewhere. Respect Reduce Transparency.
- **FR-042** Release builds MUST be Developer ID signed, use the Hardened Runtime, be notarised and be stapled (ADR-0006).
- **FR-043** In-app updates via Sparkle 2 with EdDSA-signed appcasts. This requires its own ADR first, because it adds the only network access.
  [NEEDS CLARIFICATION: should automatic update checks default to on or off?]
- **FR-044** Every control MUST have a VoiceOver label and be keyboard reachable.
- **FR-045** "Copy diagnostics" MUST export a scrubbed report (firmware, states, error codes; no MAC or serial).

## Non-functional requirements

- **NFR-001 No network.** The app makes no network connections and has no `network.client` entitlement.
  The only planned exception is the Sparkle appcast host (FR-043, after its ADR).
- **NFR-002 No account, no telemetry, no analytics, no remote crash reporting.**
- **NFR-003 Single BMAP client.** Blizzard MUST never try to evict another client. If the Bose app holds
  the link, Blizzard reports "busy". [NEEDS CLARIFICATION: hold the channel while running, or release it
  when idle so a phone can connect? This is measured in PLAN T011. The proposed default is to release
  after 60 s idle.]
- **NFR-004 Untrusted device.** Every byte from the headset is bounds-checked. A malformed or hostile
  payload MUST produce an error, never a crash or an out-of-bounds read (fuzzed in M4).
- **NFR-005 Responsiveness.** The main thread never blocks on Bluetooth. Target: a mode switch is
  reflected within 1.5 s on a connected headset (bosectl's protocol settle alone is 200 ms).
- **NFR-006 Idle cost.** There are no busy loops. Polling while the panel is closed runs no more often than every 5 min.
- **NFR-007 Privacy.** MAC addresses and serials are logged with `os_log` `.private` and never written to committed fixtures.
- **NFR-008 Code quality.** Swift 6 language mode with complete strict concurrency, zero warnings, and C++17 for the shim.
- **NFR-009 Platform.** [NEEDS CLARIFICATION: minimum macOS. The proposal is macOS 15.0, with Liquid Glass gated by
  `if #available(macOS 26, *)`. Requiring macOS 26 would remove that branch.]

## Acceptance criteria

M0
- WHEN `blizzard-probe --read 0.5` runs against a paired gen-1 headset THE SYSTEM SHALL print a firmware
  string such as `1.6.7+g6ebabd2` and exit 0.
- WHEN any component asks the shim to send operator SET, or any packet to blocks 3, 8, 18 or 20 THE SYSTEM
  SHALL refuse it with `BLZ_ERR_DENIED` and send zero bytes. This is a unit test for every profile.
- WHEN the fake transport makes a bosectl call throw THE SYSTEM SHALL return an error status to Swift and keep running.

M1
- WHEN the panel opens and the headset is connected THE SYSTEM SHALL show battery, firmware, name and current mode within 3 s.
- WHEN the headset disconnects THE SYSTEM SHALL show "disconnected" within 5 s and reconnect automatically when it returns.
- WHEN the channel cannot be opened because it is busy THE SYSTEM SHALL show "Headphones busy: close the Bose app
  on your phone, then Retry" and SHALL NOT retry more than 4 times without user action.
- WHEN the headset returns a payload shorter than the parser needs THE SYSTEM SHALL show "unknown" for that field and log the error code.

M2
- WHEN the user picks a mode THE SYSTEM SHALL send exactly one START [31.3], then GET [31.3], and show the
  mode only after the read-back matches.
- WHEN the read-back differs from the request THE SYSTEM SHALL show the actual mode and a non-blocking error.
- WHEN the user sets self-voice to a level THE SYSTEM SHALL send SETGET [1.11] `[1, level]` and display the level from the reply.

M3
- WHEN a M3 feature's PROTOCOL.md entry lacks a Blizzard-verified fixture THE SYSTEM SHALL not show its control.
- WHEN the headset answers a write with error 5 THE SYSTEM SHALL disable that control for this firmware and say why.

M4
- WHEN a release archive is built THE SYSTEM SHALL pass `spctl` assessment and `stapler validate`. See `/release`.
- WHEN Reduce Transparency is on THE SYSTEM SHALL render without glass effects.

## End-to-end verification

Run this on hardware for each milestone checkpoint: pair the headset, launch Blizzard, open the panel, and record
battery, firmware and mode. Switch through every listed mode and confirm each by ear and in the UI. Toggle self-voice.
Turn the headset off and on and confirm reconnect. Start the Bose app on the phone and confirm the busy
state. Paste the scrubbed diagnostics into the PLAN checkpoint entry.

## Definition of done (every task)

1. `swift build` and `swift test` pass (once the Xcode project exists, `xcodebuild test` passes too). Paste the command output into the PR/turn.
2. No new warnings. Strict concurrency is clean.
3. Every new parser has a fixture test. Every new write has an allowlist entry, a deny-list test and a read-back.
4. `docs/PLAN.md` is ticked with date and commit. PROTOCOL.md is updated if protocol knowledge changed. An ADR exists if a decision changed.
5. No edits under `Vendor/bosectl/`. No secrets. No network code.
