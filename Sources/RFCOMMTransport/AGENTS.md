# Sources/RFCOMMTransport: Swift IOBluetooth transport

This directory adds to the root AGENTS.md. Design: ARCHITECTURE §4, §7 and §8, and ADR-0003.

This is the **only** target that may `import IOBluetooth`. Use `@preconcurrency import IOBluetooth`. CI greps for this.

## Files (planned)

- `BMAPThread.swift`: a dedicated `Thread` with its own run loop. It owns every IOBluetooth object and the shim session.
- `IOBluetoothLink.swift`: `BMAPLink` conformance and `IOBluetoothRFCOMMChannelDelegate`. Provides the blocking `sendRecv`.
- `Discovery.swift`: paired-device lookup and channel resolution.
- `DenyList.swift`: an independent re-check of the absolute deny-list before every write.

## Gotchas (each one bit somebody)

- **Run loop required.** IOBluetooth delivers delegate callbacks on the run loop of the thread that opened the channel
  [INFERRED]. Opening from Swift `async`/`Task` code (the cooperative pool has no run loop) timed out with
  `waitforChanneOpen timed out` and error `-536870212` (0xE00002BC) (Apple Forums 713749). Open and use the channel only on `BMAPThread`.
- **No re-entrancy.** `sendRecv` pumps `RunLoop.current.run(mode: .default, before: now + 10 ms)` while waiting.
  Jobs must never be run-loop sources: no `perform(_:on:)` and no timers for jobs. Otherwise a pump would run a second shim call
  nested inside the first. Dequeue jobs only from the thread's top-level loop, and keep the debug assertion.
- **Not default-MainActor.** This target must not enable Swift 6.2 default MainActor isolation. Delegate methods are
  `nonisolated` and assert `Thread.current === owner`.
- **Copy bytes immediately.** The pointer passed to `rfcommChannelData(_:data:length:)` is valid only during the callback.
  Copy it into `[UInt8]` before queueing.
- **Writes.** `writeSync` takes a mutable pointer and a `UInt16` length. Chunk to `getMTU()`. Never call it on the main thread.
- **Timings must match bosectl** (`transport.py` / `transport.cpp`). Tests assert these as constants:
  - `performSDPQuery` pumped for **1.5 s**. Do **not** wait for `sdpQueryComplete`: on macOS 15.5 it never fires after a reconnect.
  - baseband `openConnection` ≤ **5 s**;
  - `openRFCOMMChannelSync` + `rfcommChannelOpenComplete` ≤ **3 s**;
  - flush startup packets for **0.5 s**;
  - per request: discard stale bytes (≤ 64 × 4096), write, wait **200 ms**, then ≤ **3 s** for the first chunk;
  - drain until **500 ms** of silence, with hard caps of **5 s / 64 KiB**.
- **Channels.** Try the SDP result for UUID `00000000-deca-fade-deca-deafdecacaff`, then the cached channel, then **2**, then 8 and 9. A fallback
  channel counts only if GET [0.5] answers. Never open 14, 22 (diagnostic stream), 25 or 26.
- **Reconnect.** Gen 1 refuses connections for about 1 s after a close. Wait ≥ 1.5 s, then retry at 500 / 1000 / 2000 ms. macOS
  errors carry no errno, so do not port bosectl's errno-based retry logic.
- **Busy.** Another BMAP client, such as the Bose app, may hold the link. Report busy, never retry in a loop, and never try to evict it.
- **Closed.** `rfcommChannelClosed` must fail any in-flight `sendRecv` with `.closed`. Do not leave it waiting out the 3 s timeout.
- Keep `IOBluetoothUserNotification` objects alive, and `unregister()` them on teardown.
- The method names for SDP and notifications are [UNVERIFIED]. Check them against the Xcode 26 headers
  (`IOBluetoothDevice.h`, `IOBluetoothRFCOMMChannel.h`) before relying on them.

## Testing

Production code depends on the `BMAPLink` protocol. Tests use `ReplayLink` / `SimLink` (in BlizzardCore tests). Hardware checks
are manual (`[HW]` tasks in PLAN). Never write a test that needs Bluetooth to pass in CI.
