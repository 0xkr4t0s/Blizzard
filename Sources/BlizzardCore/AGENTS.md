# Sources/BlizzardCore: Swift async API

This directory adds to the root AGENTS.md. Design: ARCHITECTURE §3-§6 and §8.

## Files (planned)

- `DeviceSession.swift`: an `actor` with `connect()`, `battery()`, `firmware()`, `name()`, `modeIndex()`, `modes()`,
  `setMode(_:announce:)` and `setSelfVoice(_:)`. Each is `async throws(BlizzardError)` and returns Sendable value types.
- `ShimBridge.swift`: owns the `blz_session*`, the `@convention(c)` trampoline, and `Unmanaged` retain/release of the link context.
- `Models.swift` (`Battery`, `Mode`, `SelfVoiceLevel`, `DeviceInfo`), `BlizzardError.swift`, `ReconnectPolicy.swift`.

## Rules specific to this directory

- **No IOBluetooth import here.** Talk to `BMAPThread` / `BMAPLink` from RFCOMMTransport only.
- **One hop per shim call.** Run every `blz_*` call inside `await bmapThread.run { ... }`, and resume the `CheckedContinuation` exactly
  once, including on error and on cancellation. Never call `blz_*` from the actor's own executor.
- **Map every `blz_status`.** Use the ARCHITECTURE §6 table. `BLZ_ERR_DENIED` and `BLZ_ERR_INVALID_ARG` are programmer bugs:
  `assertionFailure` in Debug, and log at fault level in Release.
- **Writes go through read-back.** `setMode` returns the index read back from GET [31.3], not the requested one. Callers must
  display the returned value.
- **Validate before the shim.** Check mode indices against the last `modes()` result (gen 1 answers indices 0-9 only) and self-voice
  levels against 0-3. The shim validates again; defence in depth is intended.
- **`ReconnectPolicy` is pure.** It is a state machine whose inputs are events and clock ticks and whose outputs are actions, so tests use a fake clock.
  Initial values: settle ≥ 1.5 s after close, retries at 500/1000/2000 ms, at most 4 attempts, and busy → wait for the user.
- **Unmanaged context lifetime.** Retain when the session is created and release in `blz_session_destroy`'s caller, after the
  thread has stopped issuing calls. A dangling ctx means a use-after-free from C++.

## Tests

`Tests/BlizzardCoreTests/`:
- `ReplayLink` replays `Fixtures/lonestarr/<fw>/*.hex` and fails on any unexpected request bytes.
  That catches accidental extra commands.
- `SimLink` is a stateful fake headset for previews.
