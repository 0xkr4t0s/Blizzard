# BMAP protocol reference for QC Ultra Headphones (1st Gen)

Target: Bose QuietComfort Ultra Headphones, 1st Gen (2023), codename **lonestarr**, Bluetooth product ID **0x4066**.
Last reviewed: 2026-10-12. This file is the single source of truth for which addresses Blizzard may touch.
`Sources/BMAPShim/allowlist.cpp` must match the **Blizzard policy** column. If they disagree, the code is wrong.

Change this file only by following `.claude/skills/verify-bmap-feature/SKILL.md`. Never upgrade a status
because something "looks the same as gen 2".

## Status legend

External evidence (what other people observed):

- **CONFIRMED-GEN1**: observed on real QC Ultra 1st Gen hardware. Sources: airvzxf/bose-connect-app-linux
  (firmware 1.6.7) or NerdySouth/bozo ("developed and tested with QC Ultra Headphones (Gen 1)").
- **GEN2-ONLY**: observed on QC Ultra 2nd Gen (wolverine, 0x4082) or another product, never on gen 1.
- **UNVERIFIED**: comes from APK decompilation, an enum or inference. Nobody has reported it from gen 1 hardware.

Blizzard verification (what *we* captured): `—` means not yet. Otherwise it gives firmware plus a fixture
path under `Fixtures/lonestarr/<fw>/`. Writes need a Blizzard-verified entry before they leave `GATED`.

Blizzard policy values: `GET` (read allowed in app) · `PROBE` (GET allowed only in `blizzard-probe`) ·
`SETGET` / `START` (that write is allowed in app) · `GATED` (blocked until verified) · `DENY` (never sent).

## Packet format

`[fblock, function, flags, length, payload...]`. Flags = `(device_id << 6) | (port << 4) | operator`.
Device ID and port are 0 for headphones. The length is 1 byte, so the payload is 0-255 bytes. There is no
checksum and no framing on RFCOMM. One read can contain **several concatenated packets** plus
**unsolicited STATUS** frames (for example [31.3] on connect), so walk the buffer by its length bytes.
bosectl's `select_reply()` matches replies by address and throws `desync_error` if only other addresses arrive.
Sources: [bosectl NOTES.md](https://github.com/aaronsb/bosectl/blob/main/NOTES.md),
[bozo packet.rs](https://github.com/NerdySouth/bozo/blob/main/crates/bozo-proto/src/bmap/packet.rs),
[bosectl connection.h L360-389](https://github.com/aaronsb/bosectl/blob/70570b29c1d3c9ba775b08a29eaea72385de27b5/cpp/src/connection.h).

| Op | Name | Direction | Blizzard policy |
|---|---|---|---|
| 0 | SET | command | **DENY always**: needs cloud ECDH auth |
| 1 | GET | command | allowed on allowlisted addresses only |
| 2 | SETGET | command | allowed only where the table says `SETGET` |
| 3 | STATUS | response | parsed with bounds checks |
| 4 | ERROR | response | payload[0] = error code (table below) |
| 5 | START | command | allowed only where the table says `START` |
| 6 | RESULT | response | success for START |
| 7 | PROCESSING | response | also success for START: applied asynchronously, so read back |

## Error codes (payload[0] of an op-4 reply)

| Code | Name | Blizzard handling |
|---|---|---|
| 1 | Length | bug in our payload: stop, do not retry |
| 3 / 4 | FblockNotSupp / FuncNotSupp | mark the feature unavailable for this firmware |
| 5 | OpNotSupp (auth needed) | mark the feature unavailable. Never attempt auth |
| 6 | InvalidData | bug in our payload: stop |
| 8 | Runtime (e.g. preset locked) | show "this mode can't be edited" |
| 9 | Timeout · 12 Busy | transient: one retry, then surface it |
| 0, 2, 7, 10, 11, 15, 20, 0xFF | other | log the code and surface a generic error |

Codes 11, 12 and 0xFF come only from bozo; code 15 comes only from bosectl.
Sources: [bosectl NOTES.md](https://github.com/aaronsb/bosectl/blob/main/NOTES.md),
[bozo BMAP.md](https://github.com/NerdySouth/bozo/blob/main/docs/BMAP.md).

## Transport facts (gen 1)

- **RFCOMM channel 2** (CONFIRMED-GEN1; QC35 uses 8). bosectl probes the configured channel, then 2, 8 and 9,
  confirming each with GET [0.5]. Channels 14, 25 and 26 accept a socket but do not speak BMAP. On QCU2,
  channel 22 is a diagnostic/log stream and must never be opened.
  [airvzxf README](https://github.com/airvzxf/bose-connect-app-linux/blob/main/README.md),
  [bosectl prince doc](https://github.com/aaronsb/bosectl/blob/main/docs/quietcomfort-headphones-prince.md).
- SDP service UUID `00000000-deca-fade-deca-deafdecacaff` (`BMAP_UUID` in bosectl `catalog.h`).
- **Init:** send GET [0.1] `00 01 01 00` on every connect. The reply `00 01 03 05` is followed by a
  5-byte version, which we discard. [airvzxf connection.rs](https://github.com/airvzxf/bose-connect-app-linux/blob/main/crates/bose-connect/src/connection.rs).
- **Reconnect window:** "The QC Ultra refuses a new connection for about a second after the previous one closed" (airvzxf, same file).
- **Timings** (bosectl transports): settle 200 ms after each write, then wait up to 3 s for the first chunk.
  Drain mode collects until 500 ms of silence. The macOS reference also pumps SDP for 1.5 s, waits up to 5 s
  for baseband, up to 3 s for the channel to open, and flushes for 0.5 s after open.
  [bosectl transport.cpp L108-152](https://github.com/aaronsb/bosectl/blob/70570b29c1d3c9ba775b08a29eaea72385de27b5/cpp/src/transport.cpp),
  [transport.py L89-213](https://github.com/aaronsb/bosectl/blob/70570b29c1d3c9ba775b08a29eaea72385de27b5/python/pybmap/transport.py).
- **One client at a time.** Quiet Rebellion requires the Bose app to be closed, and quietrebellion's Windows
  port notes that the connection fails while the Bose app holds RFCOMM. It is UNVERIFIED whether a phone
  holding the link blocks a Mac (PLAN T011).
- Firmware tested by others: **1.6.7** (`1.6.7+g6ebabd2`, 5 March 2024), the latest gen-1 release on
  [Bose HK support](https://www.bose.hk/en_hk/support/articles/HC2300/productCodes/QCUH-HEADPHONEARN/article.html).
  Gen 2 runs a separate firmware line (8.2.x / 2.0.x).

## Address table

| Addr | Setting | Ops / payload (as reported) | External status | Blizzard verified | Blizzard policy | MS |
|---|---|---|---|---|---|---|
| 0.1 | BMAP version / init | GET → `00 01 03 05` + 5 bytes | CONFIRMED-GEN1 [a1] | — | GET | M0 |
| 0.3 | Product ID + variant | GET → `<pid_hi> <pid_lo> <variant>` (BE) | CONFIRMED-GEN1 [a2] | — | GET | M0 |
| 0.5 | Firmware | GET → ASCII, length from header | CONFIRMED-GEN1 [a2] | — | GET | M0 |
| 0.6 | BT MAC | GET → 6 bytes | CONFIRMED-GEN1 [a2] | — | PROBE | M0 |
| 0.7 | Serial | GET → `<len> <ascii>` | CONFIRMED-GEN1 [a3] | — | PROBE (never log) | M0 |
| 0.15 | Marketing name | GET → ASCII | GEN2-ONLY [b2] | — | PROBE | M0 |
| 1.2 | Device name | GET → `[0x00, utf8…]`; SETGET `<len> <name>` (no leading 0), ≤31 bytes | read CONFIRMED-GEN1 [z1]; write UNVERIFIED | — | GET; write GATED | M1 / M3 |
| 1.3 | Voice prompts + language | gen 1 GET returns 7 bytes; language bit 6 is set, so mask the low 5 bits | read partly CONFIRMED-GEN1; write UNVERIFIED [a4] | — | PROBE; write GATED | M3 |
| 1.4 | Auto-off / standby | gen 1 GET `a0 00 05` (undecoded). bozo writes SETGET 1 byte of minutes | UNVERIFIED (read/write conflict) [a2][z2] | — | PROBE; write GATED | M3 |
| 1.5 | CNC (legacy) | GET 3 bytes; byte order disputed (see Conflicts) | GET works; **SETGET → error 5 on gen 1** CONFIRMED-GEN1 [z1] | — | PROBE; SETGET **DENY** | M3 (read) |
| 1.6 | ANR (QC35-style) | discrete levels on QC35 | not applicable / untested | — | DENY | — |
| 1.7 | EQ, 3-band | GET 3× `[min -10, max +10, cur int8, band]`; SETGET `02 <int8> <band 0/1/2>` | register present on gen 1 [a4]; write GEN2-ONLY | — | PROBE; write GATED | M3 |
| 1.9 | Buttons / shortcut | QCU2 button 0x80 long-press actions | GEN2-ONLY [b1] | — | PROBE; write GATED | later |
| 1.10 | Multipoint | SETGET 1 byte; SET auth-gated | GEN2-ONLY [b1] | — | PROBE; write GATED | later |
| 1.11 | Self-voice / sidetone | SETGET `02 01 <lvl>` (persist=1; 0 off, 1 high, 2 med, 3 low) → STATUS `03 01 <lvl> 0f` | **CONFIRMED-GEN1** [a2] | — | GET (if sweep confirms), **SETGET** | M2 |
| 1.16 | On-head detection | APK enum | UNVERIFIED [z3] | — | PROBE | — |
| 1.24 / 1.27 | Auto play-pause / auto-answer | SETGET 1 byte 0/1 | GEN2-ONLY [b1] | — | PROBE; write GATED | later |
| 1.29 | Auto-aware | APK enum | UNVERIFIED [z3] | — | PROBE | — |
| 2.2 | Battery | GET → gen 1 `64 ff ff 00` = pct, minutes BE (0xFFFF unknown), component | **CONFIRMED-GEN1** [a2][z1] | — | GET | M1 |
| 2.5 / 2.9 | Charger / in-ear | APK enum | UNVERIFIED [z3] | — | PROBE | — |
| 4.1-4.3 | Connect / disconnect / remove device | START + 6-byte MAC | UNVERIFIED | — | **DENY** (4.3: see SECURITY.md) | — |
| 4.4 / 4.5 | Paired devices / per-device info | GET | CONFIRMED-GEN1 [a3] | — | PROBE (MACs: scrub) | — |
| 4.7 | Clear device list | — | — | — | **DENY** | — |
| 4.8 | Pairing mode | START 1 byte | GEN2-ONLY | — | DENY | — |
| 4.12 | Routing / source switch | START `[0x82, mac]` | GEN2-ONLY; refused on QCU2 fw 2.0.4 [b3] | — | DENY | — |
| 5.1 | Active source | GET | GEN2-ONLY | — | PROBE | — |
| 5.3 | Media keys | START 1 byte | **gen 1 → ERROR 0x0C Busy** [a5] | — | DENY | — |
| 5.5 | Volume | SETGET `01 <lvl>` → `<max 0x1F> <lvl>`; out-of-range values are clamped silently | CONFIRMED-GEN1 [a2] | — | PROBE (non-goal) | — |
| 7.4 | Power off | START `00` | likely gen 1 (bozo TUI), no capture [z2] | — | **DENY** (see SECURITY.md) | — |
| 31.2 | AudioModes capabilities | GET → `[nBose, nUser, rsv×3, flags, minFav]` | UNVERIFIED (APK) [z1] | — | PROBE | M2 |
| 31.3 | Current mode | GET → `01 <idx>`; START `02 <idx> <prompt 0/1>` → RESULT `<idx>` | **CONFIRMED-GEN1** [a2][z2] | — | GET, **START** | M1 / M2 |
| 31.4 | Default (power-on) mode | SETGET timed out on QCU2 | UNVERIFIED | — | PROBE | — |
| 31.6 | Mode config | GET `01 <idx>`; name = 32 bytes at payload offset 6; empty slot "None"; gen 1 answers idx 0-9 and errors on 10 | GET **CONFIRMED-GEN1** [a2]; STATUS/SETGET length unknown | — | GET (idx 0-9); write GATED | M1 / M3 |
| 31.8 | Favourites | SETGET | GEN2-ONLY | — | PROBE | later |
| 31.9 | Mode reset | START (semantics unknown) | — | — | **DENY** | — |
| 31.10 | Live CNC/spatial/wind/ANC | SETGET 5 bytes on QCU2 | GEN2-ONLY; prince → FuncNotSupp [b4] | — | PROBE; write GATED | M3 |
| 31.11 | Supported mode names | GET bitmap of prompt IDs | UNVERIFIED [z1] | — | PROBE | M2 |
| 3.x, 8.x, 18.x, 20.x | FirmwareUpdate, Debug, Authentication, Cloud (0x14) | — | — | — | **DENY: every op, including GET** | — |
| 7.5, 7.6, 7.7, 7.11 | Factory default, ship mode, ANR-only, reset | — | — | — | **DENY** | — |

Sources:
[a1] [airvzxf connection.rs](https://github.com/airvzxf/bose-connect-app-linux/blob/main/crates/bose-connect/src/connection.rs) ·
[a2] [airvzxf protocol.rs](https://github.com/airvzxf/bose-connect-app-linux/blob/main/crates/bose-connect/src/protocol.rs) ·
[a3] [airvzxf README](https://github.com/airvzxf/bose-connect-app-linux/blob/main/README.md) ·
[a4] [airvzxf TODO.md](https://github.com/airvzxf/bose-connect-app-linux/blob/main/TODO.md) ·
[a5] [airvzxf types.rs](https://github.com/airvzxf/bose-connect-app-linux/blob/main/crates/bose-connect/src/types.rs) ·
[b1] [bosectl NOTES.md](https://github.com/aaronsb/bosectl/blob/main/NOTES.md) ·
[b2] [bosectl captures/](https://github.com/aaronsb/bosectl/tree/main/captures) ·
[b3] [bosectl issue #44](https://github.com/aaronsb/bosectl/issues/44) ·
[b4] [bosectl prince doc](https://github.com/aaronsb/bosectl/blob/main/docs/quietcomfort-headphones-prince.md) ·
[z1] [bozo BMAP.md](https://github.com/NerdySouth/bozo/blob/main/docs/BMAP.md) ·
[z2] [bozo README](https://github.com/NerdySouth/bozo/blob/main/README.md) ·
[z3] [bozo enums.rs](https://github.com/NerdySouth/bozo/blob/main/crates/bozo-proto/src/bmap/enums.rs)

## Conflicts and traps

- **[1.5] byte order.** bosectl parses `[numSteps, step, flags]`; bozo parses `[step, numSteps, flags]`.
  QCU2's `0b 00 03` fits bosectl's order. Resolve it on gen 1 by capture before displaying any CNC value.
- **Product-info IDs.** bozo's enum says FIRMWARE_VERSION=0x04 and PRODUCT_ID_VARIANT=0x05. Hardware reads say
  firmware is at 0.5 and PID at 0.3. Trust the hardware reads.
- **bosectl v0.5.0 QCU2 ModeConfig parser** reads wind block at byte 45. Open PR #43 says it is byte 46 on fw
  8.2.20. Do not reuse `parse_mode_config_qc_ultra2` for gen 1 unless a fixture proves the layout.
- **ModeConfig length on gen 1 is unknown.** QCU2 uses a 48-byte STATUS and a 40-byte SETGET. prince/QC45 use
  47 / 39 bytes with no ancToggle, and a 40-byte write there returns a Length error. Name offset 6 holds on
  gen 1, so the layout is probably one of these two (inferred). Presets reject SETGET with error 8. Never
  write presets. QCU2 presets are 0-3 (Quiet, Aware, Immersion, Cinema); gen 1 probably has only 0-2 (UNVERIFIED).
- **[1.4] read is 3 bytes but bozo writes 1 byte.** Do not write until it is decoded.
- **No error ≠ accepted.** Gen 1 clamps out-of-range volume silently. Always read back after a write.
- **Firmware changes the surface.** QCU2 fw 2.0.4 returns FblockNotSupp for all of block 31. Detect features
  at runtime, per firmware.
- **Auth gating is per (block, function, operator)**, not per block. Branch on errors 5, 3/4 and 8.

## Open questions (tracked in SPEC.md as [NEEDS CLARIFICATION])

1. Does gen 1 accept SETGET on [1.7] EQ without auth?
2. What are the gen 1 [31.6] STATUS and SETGET lengths, and does offset 3 carry an "editable" flag?
3. Does gen 1 have [31.10]? If not, live CNC/spatial means "write a custom slot, then START [31.3]" (inferred).
4. How many presets does gen 1 have, and where do the user slots start?
5. What does `a0 00 05` in [1.4] mean?
6. Does a phone running the Bose app block the Mac's RFCOMM client?
