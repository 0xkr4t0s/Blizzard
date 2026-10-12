# Blizzard: architecture

Status: **proposed** (2026-10-12). Nothing is built yet.
Marking used below:
- **[UNVERIFIED]**: a design assumption that an M0 spike in `docs/PLAN.md` must confirm.
- **[INFERRED]**: reasoned from the sources, not observed.

Decisions are recorded in `docs/adr/`. Protocol facts live in `docs/PROTOCOL.md`.

## 1. Layers

```
┌───────────────────────────────────────────────────────────────┐
│ App/  SwiftUI: MenuBarExtra(.window), panel views, Settings    │  main thread only
├───────────────────────────────────────────────────────────────┤
│ App/DeviceStore.swift  @MainActor @Observable DeviceState      │  never imports IOBluetooth
├───────────────────────────────────────────────────────────────┤
│ Sources/BlizzardCore  actor DeviceSession: async throws API,   │  Sendable value types
│   models, BlizzardError, ReconnectPolicy, ShimBridge           │
├──────────────────────────── hops onto BMAPThread ─────────────┤
│ Sources/BMAPShim  C header bmap_shim.h → C++17 façade          │  every entry: try/catch(...)
│   • command allowlist + deny-list (choke point)                │
│   • lonestarr_config.hpp, parsers_gen1.hpp (bounds-checked)    │
│   • CallbackTransport : bmap::Transport ──────────┐            │
├───────────────────────────────────────────────────┼───────────┤
│ Vendor/bosectl/cpp/src (submodule @70570b2)       │            │  read-only
│   protocol.h · device.h · devices.h ·             │            │
│   connection.h (BmapConnection) · catalog.h ·     │            │
│   errors.h · transport.h (abstract base only)     │            │
├───────────────────────────────────────────────────┼───────────┤
│ Sources/RFCOMMTransport  ◄── C fn ptr + void* ctx ┘            │  runs on BMAPThread
│   BMAPThread (own RunLoop) · IOBluetoothLink (delegate) ·      │
│   Discovery · DenyList (second, independent check)             │
├───────────────────────────────────────────────────────────────┤
│ IOBluetooth: IOBluetoothDevice / IOBluetoothRFCOMMChannel      │
└───────────────────────────────────────────────────────────────┘
                         ⇅ Bluetooth Classic RFCOMM, channel 2
                 QC Ultra Headphones (1st Gen) · lonestarr · 0x4066
```

These parts of bosectl are **not** used:
- `transport.cpp`: its macOS branch throws "not supported on macOS".
- `discovery.cpp`: returns `nullopt` on Apple platforms.
- `bmap.h`: its `connect()` / `detail::open_transport` reference `RfcommTransport`.

The shim includes the individual headers directly, so no vendored `.cpp` is compiled.
Sources: [transport.cpp L122-147](https://github.com/aaronsb/bosectl/blob/70570b29c1d3c9ba775b08a29eaea72385de27b5/cpp/src/transport.cpp),
[discovery.cpp L89-97](https://github.com/aaronsb/bosectl/blob/70570b29c1d3c9ba775b08a29eaea72385de27b5/cpp/src/discovery.cpp),
[bmap.h L212-353](https://github.com/aaronsb/bosectl/blob/70570b29c1d3c9ba775b08a29eaea72385de27b5/cpp/src/bmap.h).

## 2. Directory layout

```
Blizzard/
├── AGENTS.md  CLAUDE.md  README.md
├── Package.swift                 SwiftPM: BMAPShim, RFCOMMTransport, BlizzardCore, BlizzardProbe + tests
├── Blizzard.xcodeproj            app target only; depends on the local package
├── App/                          SwiftUI app (BlizzardApp.swift, DeviceStore.swift, Views/, Info.plist,
│                                 Blizzard.entitlements)                       ← AGENTS.md
├── Sources/
│   ├── BMAPShim/                 C++17 façade; public C API in include/bmap_shim.h ← AGENTS.md
│   ├── RFCOMMTransport/          IOBluetooth, BMAPThread, Discovery           ← AGENTS.md
│   ├── BlizzardCore/             DeviceSession, models, errors, reconnect     ← AGENTS.md
│   └── BlizzardProbe/            `blizzard-probe` read-only sweep/replay CLI (dev tool)
├── Tests/
│   ├── BMAPShimTests/            Swift Testing through the C API: allowlist, exceptions, parsers
│   ├── BlizzardCoreTests/        ReplayLink/SimLink session tests
│   └── Fuzz/                     libFuzzer harness (M4)
├── Fixtures/lonestarr/<fw>/      scrubbed request/response hex + expected JSON  ← AGENTS.md
├── Vendor/
│   ├── bosectl/                  git submodule, pinned 70570b2 (v0.5.0). DO NOT EDIT
│   └── patches/                  only if an ADR allows a local patch (empty by default)
│                                 (Vendor/AGENTS.md covers both; nothing is written inside the submodule)
├── scripts/                      release.sh (M4)
├── docs/                         SPEC, ARCHITECTURE, PLAN, PROTOCOL, SECURITY, adr/
└── .claude/                      settings.json (deny rules), skills/
```

## 3. Components

**App (SwiftUI).** The app is a `MenuBarExtra` in `.menuBarExtraStyle(.window)` with `LSUIElement = YES`.
Preferences use a `Settings` scene, and opening it calls `NSApp.activate()` first. Colours are semantic and icons are SF Symbols.
On macOS 26, use `GlassEffectContainer` + `glassEffect(_:in:)` sparingly, on the mode buttons only, because
the panel chrome is already glass. Gate it with `if #available(macOS 26, *)` and respect Reduce Transparency.
Launch at login uses `SMAppService.mainApp` (M4).
This is the same house style as Purrifier: native Swift, menu bar first, light and dark.
Sources: [GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer.md),
[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice.md).

**DeviceStore** (`@MainActor @Observable`). Holds `DeviceState`: connection, battery, firmware, name,
modeIndex, modes, selfVoice, and a feature map. It only calls `DeviceSession` and never blocks.
It updates state only after a read-back, so the UI never shows an optimistic value as fact.

**BlizzardCore.**
- `actor DeviceSession` exposes `connect()`, `battery()`, `firmware()`, `name()`, `modeIndex()`,
  `modes()`, `setMode(_:announce:)` and `setSelfVoice(_:)`. Each is `async throws(BlizzardError)` and returns Sendable value types.
- `ShimBridge` owns the `blz_session*`, the C callback trampoline and the `Unmanaged` context.
- `ReconnectPolicy` is a pure, testable state machine (§8).

**RFCOMMTransport.** This is the only target that may `import IOBluetooth` (CI greps for it).
- `BMAPThread` is a dedicated `Thread` with its own run loop. It owns every IOBluetooth object and the shim session.
- `IOBluetoothLink: BMAPLink` implements the blocking `sendRecv`.
- `Discovery` handles paired-device lookup and channel resolution.
- `DenyList` re-checks every outgoing header independently of the C++ allowlist.

**BMAPShim** (C++17, plain C public header). Its C API is the only surface Swift sees (ADR-0002). Proposed, not final:

```c
typedef enum { BLZ_OK = 0, BLZ_ERR_CONNECT, BLZ_ERR_BUSY, BLZ_ERR_TIMEOUT, BLZ_ERR_CLOSED,
  BLZ_ERR_DEVICE, BLZ_ERR_UNSUPPORTED, BLZ_ERR_DESYNC, BLZ_ERR_DENIED, BLZ_ERR_PARSE,
  BLZ_ERR_INVALID_ARG, BLZ_ERR_INTERNAL } blz_status;
typedef enum { BLZ_PROFILE_APP, BLZ_PROFILE_PROBE, BLZ_PROFILE_REPLAY } blz_profile;
/* Called on BMAPThread. Writes at most out_cap bytes. Must not call back into the shim. */
typedef blz_status (*blz_send_recv_fn)(void *ctx, const uint8_t *pkt, size_t pkt_len, bool drain,
                                       uint8_t *out, size_t out_cap, size_t *out_len);
blz_session *blz_session_create(blz_send_recv_fn fn, void *ctx, blz_profile profile);
void        blz_session_destroy(blz_session *s);
blz_status  blz_init(blz_session *s);                                  /* GET [0.1] */
blz_status  blz_read_firmware(blz_session *s, char *buf, size_t cap);  /* GET [0.5] */
blz_status  blz_read_battery(blz_session *s, blz_battery *out);        /* GET [2.2] */
blz_status  blz_read_mode_index(blz_session *s, uint8_t *idx);         /* GET [31.3] */
blz_status  blz_read_mode_name(blz_session *s, uint8_t idx, char *buf, size_t cap); /* GET [31.6] */
blz_status  blz_set_mode(blz_session *s, uint8_t idx, bool announce, uint8_t *readback); /* START [31.3] */
blz_status  blz_set_self_voice(blz_session *s, uint8_t level, uint8_t *readback);   /* SETGET [1.11] */
blz_status  blz_probe_get(blz_session *s, uint8_t fb, uint8_t fn, const uint8_t *pl, size_t pl_len,
                          uint8_t *out, size_t cap, size_t *out_len);  /* PROBE profile only */
uint8_t     blz_last_device_error(const blz_session *s);               /* BMAP error code */
size_t      blz_last_error_message(const blz_session *s, char *buf, size_t cap);
bool        blz_packet_allowed(blz_profile p, const uint8_t *pkt, size_t len); /* for tests */
```

Built so far (T005, T007): `blz_abi_version`, `blz_session_create`/`destroy`, `blz_init`, `blz_last_device_error` and
`blz_last_error_message`, and `blz_packet_allowed` (T006), at `BLZ_ABI_VERSION` 2. Both enums end in a `*_MAX_ENUM = 0x7FFFFFFF` sentinel, so a value
outside the list that Swift passes in (for example from a link callback) is still a defined value of the C++ enum type.

`CallbackTransport : public bmap::Transport` overrides `send_recv` and `send_recv_drain`:
1. Run the allowlist check for the session's profile. A denied packet throws `blz::denied_error`.
2. Call the C function pointer with a 64 KiB buffer (heap-allocated, so `BMAPThread`'s stack size does not matter).
3. A link status other than OK becomes `blz::link_error`: CONNECT, BUSY, TIMEOUT and CLOSED pass through, and anything
   else, or a reported length larger than the buffer, becomes INTERNAL.
4. Convert the result to `std::vector<uint8_t>`.

Swift cannot subclass C++, so this class must live in C++.
Source: [transport.h L12-18](https://github.com/aaronsb/bosectl/blob/70570b29c1d3c9ba775b08a29eaea72385de27b5/cpp/src/transport.h).
The façade wraps `bmap::BmapConnection(std::unique_ptr<Transport>, DeviceConfig)`. It uses typed methods
where the lonestarr config is verified, and otherwise `get/setget/start(Addr, payload)` plus Blizzard's own gen-1 parsers.
Raw `send_raw()` is **never** exposed to Swift.

## 4. Threading model

The rule is that IOBluetooth delegates fire on the run loop of the thread that opened the channel [INFERRED from
bosectl's Python design and Apple Forums 713749]. Opening from a Swift `async` context, which runs on the cooperative
pool with no run loop, timed out with `-536870212` (0xE00002BC). The same open on the main run loop worked.
Source: [Apple Forums 713749](https://developer.apple.com/forums/thread/713749).

- **Plan A [UNVERIFIED, spike T008].** `BMAPThread` opens the channel and runs every shim call. Inside
  `sendRecv`, the thread pumps its own run loop with `RunLoop.current.run(mode: .default, before: now+10 ms)`
  until data arrives or the timeout fires. This mirrors `MacOsRfcommTransport.send_recv`. The main thread
  never touches Bluetooth.
- **No re-entrancy.** Jobs are queued in a locked FIFO and dequeued only by the thread's top-level loop, never
  from inside a pump. Do not schedule jobs as run-loop sources (`perform(_:on:)`, timers): a pump inside
  `sendRecv` would run them nested, inside a live bosectl call. Debug builds assert on this. Keep a
  `Port` on the run loop so `run(mode:before:)` blocks instead of spinning [INFERRED].
- **Plan B (if delegates don't arrive on BMAPThread).** Open the channel on the main run loop. Delegate
  callbacks copy bytes into a locked queue and signal a `DispatchSemaphore`. BMAPThread blocks on that semaphore. The
  main thread never waits on BMAPThread. Record the outcome in ADR-0003.
- **Async bridge.** `DeviceSession` calls `await bmapThread.run { ... }`. That enqueues the job and resumes a
  `CheckedContinuation` exactly once from BMAPThread. Only Sendable values cross the hop: bytes are copied
  out of the delegate's pointer into `[UInt8]` inside `rfcommChannelData`, because the pointer is valid only during that callback.
- **Swift 6.** Use `@preconcurrency import IOBluetooth`. Package targets must **not** enable default-MainActor
  isolation. That setting is for `App/` only, because the delegate methods must be `nonisolated` and run on BMAPThread.
  `IOBluetoothLink` is `@unchecked Sendable`, justified by thread confinement with `precondition(Thread.current === owner)`.
- bosectl's API is synchronous, and each round-trip is at least 200 ms, so calls are serialised (bosectl-qt does the
  same with a worker thread and mutex). Source: [bosectl-qt BmapWorker.h](https://github.com/aaronsb/bosectl-qt/blob/1712bf9/src/BmapWorker.h).

## 5. Data flow

**Read (battery).**
1. `DeviceStore.refresh()` calls `await session.battery()`, which calls `BMAPThread.run { blz_read_battery }`.
2. The façade sends `02 02 01 00` through `CallbackTransport`. The allowlist passes it for APP.
3. The C trampoline calls `IOBluetoothLink.sendRecv`, where the DenyList passes it.
4. `sendRecv` discards stale bytes (at most 64 × 4096), writes, waits 200 ms, then waits up to 3 s for the first chunk.
5. bosectl's `select_reply` finds the [2.2] frame among any unsolicited frames.
6. `parse_gen1_battery` checks `len >= 4` and returns pct and minutes, where 0xFFFF means unknown.
7. `blz_battery` becomes `Battery`, the continuation resumes, and the `@Observable` update reaches SwiftUI.

**Write (mode 4, no voice prompt).**
1. The UI calls `DeviceStore.setMode(4)`, and the state becomes `.pending`.
2. `session.setMode(4, announce: false)` checks that 4 is in the listed modes.
3. `blz_set_mode` checks `idx <= 9` and builds `1f 03 05 02 04 00`. The allowlist APP rule is
   (31, 3, START, len 2, idx 0-9, prompt 0/1).
4. The reply is RESULT or PROCESSING; ERROR becomes `BLZ_ERR_DEVICE` plus a code.
5. The façade **always** sends GET [31.3] and returns the actual index.
6. The UI shows the actual mode, plus a non-blocking error if it differs from the request.

## 6. Error model

| Source | blz_status | BlizzardError | UI |
|---|---|---|---|
| `bmap::busy_error` (**catch before** `connect_error`, its base) | BUSY | `.busy` | "Headphones busy" + Retry |
| `bmap::connect_error` | CONNECT | `.connection(reason)` | reconnect policy |
| `bmap::device_error` (`code()`) | DEVICE + code | `.device(BMAPErrorCode)` | per PROTOCOL.md error table |
| `bmap::unsupported_error` | UNSUPPORTED | `.unsupported` | hide the control |
| `bmap::desync_error` | DESYNC | `.desync` | flush, retry once |
| `std::invalid_argument` | INVALID_ARG | `.invalidArgument` | programmer bug (assert in Debug) |
| `blz::denied_error` | DENIED | `.denied` | programmer bug: log at fault level |
| `blz::parse_error` (bounds) | PARSE | `.malformedReply` | field shows "unknown" |
| link timeout / closed | TIMEOUT / CLOSED | `.timeout` / `.disconnected` | reconnect policy |
| any other `std::exception`, `catch (...)` | INTERNAL | `.internal` | generic error + diagnostics |

Sources: [errors.h](https://github.com/aaronsb/bosectl/blob/70570b29c1d3c9ba775b08a29eaea72385de27b5/cpp/src/errors.h).
Swift cannot catch C++ exceptions, and an escaping exception terminates the process.
Source: [Swift.org interop status](https://swift.org/documentation/cxx-interop/status/).

## 7. Discovery and connect sequence

1. **Discovery.** Iterate `IOBluetoothDevice.pairedDevices()` and keep devices where `productID() == 0x4066`,
   preferring `isConnected()`. This is the same approach as bosectl's `discovery.py`. That code also needs a
   non-null config, which is why it skips lonestarr. Blizzard does not.
   Source: [discovery.py L10-40](https://github.com/aaronsb/bosectl/blob/70570b29c1d3c9ba775b08a29eaea72385de27b5/python/pybmap/discovery.py).
2. **SDP.** Call `performSDPQuery(nil)` and pump for **1.5 s**. Do not wait on `sdpQueryComplete`: on macOS 15.5
   it never fires after a reconnect. Source: [Apple Forums IOBluetooth tag](https://developer.apple.com/forums/tags/iobluetooth).
   If a record for the BMAP UUID exists, read the channel with `getRFCOMMChannelID`. Method names are
   [UNVERIFIED] against the Xcode 26 headers.
3. **Channel order.** SDP result, then the per-device cached channel, then **2**, then 8 and 9. Accept a fallback channel only if GET [0.5]
   answers. Never open 14, 22, 25 or 26.
4. **Open.** Call `openConnection` (baseband), waiting ≤ 5 s. Then `openRFCOMMChannelSync(_:withChannelID:delegate:)`,
   waiting ≤ 3 s for `rfcommChannelOpenComplete`. Then pump for **0.5 s** and discard startup packets.
5. **Init.** GET [0.1], then GET [0.3]. If the PID is not 0x4066, close and report "unsupported model".
6. **Steady state.** Each `sendRecv` writes with `writeSync` on BMAPThread (never on main), chunked to `getMTU()`,
   then waits 200 ms, then waits up to 3 s for the first chunk. In drain mode it reads until 500 ms of silence, with **hard caps of 5 s and
   64 KiB** (a Blizzard addition, because the device is untrusted). `rfcommChannelClosed` raises `.disconnected`.

Sources for the timings: [transport.py L89-213](https://github.com/aaronsb/bosectl/blob/70570b29c1d3c9ba775b08a29eaea72385de27b5/python/pybmap/transport.py).

## 8. Reconnect policy (initial values, tune in T012)

- After any close, wait **≥ 1.5 s** before reopening. Gen 1 refuses connections for about 1 s after a close
  ([airvzxf connection.rs](https://github.com/airvzxf/bose-connect-app-linux/blob/main/crates/bose-connect/src/connection.rs)).
- Retry delays are 500 / 1000 / 2000 ms, giving at most 4 attempts. These are bosectl's `RETRY_DELAYS`, which it uses on Linux errnos. macOS
  errors carry no errno, so Blizzard applies them to any open failure.
- When attempts run out, the state becomes `.unavailable(reason)`. Wait for an IOBluetooth connect notification
  (`register(forConnectNotifications:selector:)`, which is [UNVERIFIED]) or for the user to press Retry. Never loop.
- A busy failure (another client holds the link) goes straight to `.busy` and waits for user action.
- Idle release: [NEEDS CLARIFICATION, SPEC NFR-003]. The proposal is to close after 60 s with the panel closed,
  and reopen on demand.

## 9. lonestarr DeviceConfig plan

`Sources/BMAPShim/lonestarr_config.hpp` defines `blizzard::qc_ultra_gen1()`, which returns a `bmap::DeviceConfig`:
1. Start from a copy of `bmap::qc_ultra2()`, which is the closest sibling.
2. Then **reset every `std::optional<Addr>` to `nullopt`**, except those whose PROTOCOL.md row is CONFIRMED-GEN1 *and*
   Blizzard-verified: firmware [0.5], product_name [1.2], battery [2.2], sidetone [1.11], current_mode [31.3]
   and mode_config [31.6] (read).

bosectl refuses features whose address is absent, so an unverified feature fails closed at lookup time.
Source: [architecture.md](https://github.com/aaronsb/bosectl/blob/70570b29c1d3c9ba775b08a29eaea72385de27b5/docs/architecture.md).

Further rules:
- Set `rfcomm_channel = 2`.
- Set `init_packet` to GET [0.1]. Before relying on this, read `connection.h` to see whether `BmapConnection` sends it.
- Read `device.h` for the meaning of `cnc_direct_setget` and `supports_anc_toggle` before setting either.
- Do not set `preset_modes` / `editable_slots` until T040 records gen-1 slot numbering.
- Keep `parse_mode_config` unset until T052. The QCU2 48-byte parser has a wrong wind offset at v0.5.0 (PR #43).

Each address enabled in the config needs a fixture test. Upstreaming follows bosectl's seven-step
"Adding a New Device" procedure (PLAN T060).

## 10. Testing seams

- `protocol BMAPLink { func open() throws; func sendRecv(_: [UInt8], drain: Bool) throws -> [UInt8]; func close() }`.
  It is called synchronously on BMAPThread and has three implementations:
  - `IOBluetoothLink` (production).
  - `ReplayLink`: maps request hex to response hex from `Fixtures/`, and fails on any unexpected request.
  - `SimLink`: a stateful fake headset for SwiftUI previews and UI tests, modelled on bosectl-qt's `SimTransport`.
- Shim tests go through the **C API**, so they exercise the real Swift→C→C++→callback→Swift path. They cover:
  - deny-list entries rejected in every profile;
  - throwing and garbage links that return status codes;
  - short, long and concatenated frames;
  - interleaved unsolicited STATUS frames.
- Upstream regression runs bosectl's own C++ tests out-of-tree with `ctest` (T004).
- Fuzzing (M4): libFuzzer over `parsers_gen1.hpp` and the frame walker. The toolchain is [UNVERIFIED], since
  Apple clang may not ship libFuzzer, so Homebrew LLVM may be needed.
- Hardware-in-the-loop: the manual checklist in SPEC §End-to-end verification. Hosted CI cannot pair Bluetooth.

## 11. Build integration

- The root `Package.swift` (Swift 6 mode) has a C++ target `BMAPShim`:
  - `cxxLanguageStandard: .cxx17`
  - `publicHeadersPath: "include"`
  - `cxxSettings: [.headerSearchPath("../../Vendor/bosectl/cpp/src")]`. Whether SwiftPM accepts this path is [UNVERIFIED].
- Because `bmap_shim.h` is pure C, Swift targets import it **without** C++ interop mode. Interop is
  viral and would otherwise spread to every dependent target.
  Source: [Swift.org build setup](https://www.swift.org/documentation/cxx-interop/project-build-setup/).
- The app target in `Blizzard.xcodeproj` links the package. It has Hardened Runtime, `com.apple.security.device.bluetooth`,
  App Sandbox (pending T013), `NSBluetoothAlwaysUsageDescription` and `LSUIElement`. It has no `network.client`.
- CI runs on `macos-26` GitHub runners: `swift build`, `swift test`, the bosectl `ctest`, and the grep checks from SECURITY.md.

## 12. Open items

- T008: Plan A vs Plan B threading.
- T010: SDP channel lookup.
- T011: phone and Bose-app conflict.
- T012: reconnect window and the 15.5 SDP bug on current macOS.
- T013: RFCOMM under App Sandbox.
- No push API exists for unsolicited STATUS. T075 investigates parsing idle frames with bosectl's
  `parse_all_responses`.
