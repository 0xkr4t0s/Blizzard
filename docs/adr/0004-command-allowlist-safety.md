# 4. Default-deny command allowlist at the transport choke point

- Status: Accepted
- Date: 2026-10-12

## Context

BMAP has no checksum and no per-command authorisation for GET, SETGET or START. Some functions act the moment they arrive:

- [7.4] START powers the headset off.
- [4.1] START may open a connection.
- Block 3 runs the OTA flow.
- The APK names the Control functions FACTORY_DEFAULT (7.5), SHIP_MODE (7.6) and RESET (7.11).

No source reports a brick, but none rules one out either. Firmware updates change what the device accepts (QCU2 fw 2.0.4 dropped
block 31), and gen 1 silently clamps some values. The gen-1 address map is mostly unverified (`docs/PROTOCOL.md`).
Blizzard is also a security portfolio piece, so a visible, testable command policy is a goal in itself.

Sources: [bosectl NOTES.md](https://github.com/aaronsb/bosectl/blob/main/NOTES.md),
[bozo enums.rs](https://github.com/NerdySouth/bozo/blob/main/crates/bozo-proto/src/bmap/enums.rs),
[bosectl issue #44](https://github.com/aaronsb/bosectl/issues/44),
[airvzxf protocol.rs](https://github.com/airvzxf/bose-connect-app-linux/blob/main/crates/bose-connect/src/protocol.rs).

## Decision

1. **Default deny.** `CallbackTransport::send_recv` parses each outbound header (fblock, function, operator, length), plus the payload
   where a rule constrains it. It forwards the packet only if the session's profile allows it:
   - **APP**: verified GETs, START [31.3], SETGET [1.11].
   - **PROBE**: GET on known functions in blocks 0, 1, 2, 4, 5 and 31 only.
   - **REPLAY**: one capture-derived write per run, which must be explicitly acknowledged.
2. **Absolute deny-list in every profile:**
   - operator SET;
   - blocks 3, 8, 18 and 20;
   - [7.5], [7.6], [7.7], [7.11] and [31.9];
   - [7.4], [4.3] and [4.7], until a future ADR adds a per-call user confirmation.
3. **Second, independent layer.** Swift `DenyList` re-checks the absolute deny-list just before `writeSync`.
4. **The typed config is the first line of defence.** The lonestarr `DeviceConfig` leaves unverified addresses `nullopt`, so bosectl
   refuses them before a packet is ever built.
5. **Read-back after every write.** The UI reflects the device's answer, not the request.
6. `docs/PROTOCOL.md` is the human-readable policy. Changes go through `/verify-bmap-feature`.

## Consequences

- New features cost a verification step (capture, replay, read-back, fixture) before they ship. This is intended.
- Every deny-list rule has a unit test per profile. A regression fails CI, which makes the policy demonstrable to reviewers.
- The allowlist can drift from PROTOCOL.md. Mitigation: review, plus a test that every APP rule names a fixture file.
- REPLAY is a deliberate escape hatch for research. It is limited to the CLI and can never bypass the absolute deny-list.
