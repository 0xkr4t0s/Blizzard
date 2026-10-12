# 3. Swift IOBluetooth RFCOMM transport injected into bosectl

- Status: Accepted. The threading detail (Plan A or B) is pending spike T008, and the result will be appended under Notes.
- Date: 2026-10-12

## Context

bosectl's C++ and Rust RFCOMM transports are Linux/BlueZ only. On macOS the C++ constructor throws, and discovery returns
`nullopt`. Only Python works on macOS. Its `MacOsRfcommTransport` uses IOBluetooth through PyObjC with these steps:
1. pump `performSDPQuery` for 1.5 s;
2. `openConnection` (baseband), waiting ≤ 5 s;
3. `openRFCOMMChannelSync`, waiting ≤ 3 s;
4. flush for 0.5 s;
5. then for each request: `writeSync`, a 200 ms settle, ≤ 3 s for the first chunk, and drain until 500 ms of silence.

It pumps `NSRunLoop` in 10 ms slices while it waits.

Gen 1 speaks BMAP on **RFCOMM channel 2** (airvzxf, firmware 1.6.7). IOBluetooth is still the only public macOS API for
Classic RFCOMM, and Apple's 2026 docs show no deprecation. Opening a channel from a Swift `async` context timed out with
`-536870212`; the same open on the main run loop worked.

Sources: [transport.cpp](https://github.com/aaronsb/bosectl/blob/70570b29c1d3c9ba775b08a29eaea72385de27b5/cpp/src/transport.cpp),
[transport.py](https://github.com/aaronsb/bosectl/blob/70570b29c1d3c9ba775b08a29eaea72385de27b5/python/pybmap/transport.py),
[airvzxf README](https://github.com/airvzxf/bose-connect-app-linux/blob/main/README.md),
[IOBluetoothRFCOMMChannel](https://developer.apple.com/documentation/iobluetooth/iobluetoothrfcommchannel.md),
[Apple Forums 713749](https://developer.apple.com/forums/thread/713749).

## Alternatives

- **BLE GATT via CoreBluetooth.** NerdySouth/bozo has done this on macOS with QC Ultra Gen 1:
  - service `febe`;
  - secure characteristic `C65B8F2F-…`, unsecure `D417C028-…`;
  - a 1-byte segment header with up to 19 data bytes per write.

  It avoids IOBluetooth entirely and is a **viable fallback**. It was not chosen because bosectl's transport seam,
  timings and fixtures are RFCOMM-shaped, and because it is unknown whether gating differs between the BLE
  characteristics. Source: [bozo BMAP.md](https://github.com/NerdySouth/bozo/blob/main/docs/BMAP.md).
- **Objective-C++ transport** (as Chromium and Qt do). Workable, but it adds a third language to the security-critical path.

## Decision

- Implement `IOBluetoothLink` in Swift (`Sources/RFCOMMTransport`), mirroring the Python reference's sequence and timings. Add:
  - hard caps on the drain (5 s and 64 KiB);
  - an independent deny-list check.
- Expose it to bosectl through the shim's `CallbackTransport` (ADR-0002).
- All IOBluetooth objects live on one dedicated `BMAPThread` with its own run loop (Plan A).
  If T008 shows that delegates do not arrive there, use Plan B: open on the main run loop and block BMAPThread on a semaphore.
- `IOBluetooth` may be imported only in `Sources/RFCOMMTransport`.

## Consequences

- bosectl's `connect()` / `probe_channels` are not used. Blizzard re-implements channel resolution (SDP, then cache, then 2, 8, 9 with GET [0.5]).
- Known macOS quirks must be handled: SDP completion never fires after a reconnect on 15.5, and gen 1 refuses connections for about 1 s after a close.
- If both plans fail in T008, write a new ADR that supersedes this one in favour of BLE.

## Notes

(Append dated spike results here: T008 threading outcome, T010 SDP channel, T012 timings.)
