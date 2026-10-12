# Sources/BMAPShim: C++17 façade over bosectl

This directory adds to the root AGENTS.md. Design: ARCHITECTURE §3, §6 and §9, and ADR-0002 and ADR-0004. Use plan mode before changing anything here.

## Files (planned)

- `include/bmap_shim.h`: the **pure C** public API. It may include only `<stdint.h>`, `<stddef.h>` and `<stdbool.h>`, and
  uses `extern "C"` guards. It is the only thing Swift imports. Bump `blz_abi_version()` on any signature change.
- `callback_transport.hpp`: `CallbackTransport : public bmap::Transport`. It overrides `send_recv` and `send_recv_drain`, runs the
  allowlist check, then calls Swift through `blz_send_recv_fn` + `void* ctx` into a 64 KiB caller buffer.
- `facade.cpp`: implements every `blz_*` function on top of `bmap::BmapConnection`.
- `allowlist.{hpp,cpp}`: the APP / PROBE / REPLAY profiles and the absolute deny-list. This file must match `docs/PROTOCOL.md`.
- `lonestarr_config.hpp`: `blizzard::qc_ultra_gen1()`.
- `parsers_gen1.hpp`: bounds-checked parsers for gen-1 payloads.

## Rules specific to this directory

- **Exceptions stop here.** Every `extern "C"` function body is wrapped in a single `try`, with handlers in this order:
  1. `bmap::busy_error`: it derives from `connect_error`, so catch it first.
  2. `bmap::connect_error`, `device_error` (keep `code()`), `unsupported_error` and `desync_error`.
  3. `blz::denied_error` and `blz::parse_error`.
  4. `std::invalid_argument`, then `std::exception`, then `...`.

  Each handler stores its message for `blz_last_error_message` and returns a `blz_status`. Swift cannot catch C++
  exceptions, and an escaping one kills the app.
- **Include individual headers only:** `protocol.h`, `device.h`, `devices.h`, `connection.h`, `catalog.h`, `errors.h`, and
  `transport.h` for the abstract base. **Do not include `bmap.h`**: its `connect()` drags in `RfcommTransport` and
  `transport.cpp`, which throws on macOS. Never instantiate `RfcommTransport`, and never compile vendored `.cpp` files.
- **No raw send to Swift.** Never expose `BmapConnection::send_raw()` or a generic write. `blz_probe_get` exists only for
  the PROBE profile and is GET-only.
- **Allowlist at the choke point.** `CallbackTransport` checks *every* outbound packet, including those bosectl builds
  internally. Parse the header first: `byte0` = fblock, `byte1` = function, `byte2 & 0x0F` = operator,
  `byte3` = length (must equal `size - 4`). A malformed header is denied.
- **Bounds checks.** Every parser takes `(const uint8_t* p, size_t n)` and checks `n` before every index. Strings from the device
  are length-limited and copied, never NUL-terminated in place. One read can contain several frames. bosectl's
  `select_reply` handles that for typed calls; our own walker must too.
- **Config discipline.** In `qc_ultra_gen1()`, an address is non-null only if its PROTOCOL.md row is CONFIRMED-GEN1 *and*
  Blizzard-verified with a fixture. Read `device.h` before setting `cnc_direct_setget`, `supports_anc_toggle`,
  `preset_modes`, `editable_slots` or `init_packet`. Do not guess.
- **Known upstream traps:**
  - v0.5.0's `parse_mode_config_qc_ultra2` reads wind block at byte 45. PR #43 says it is at 46. Do not use it for gen 1.
  - The [1.5] CNC byte order is disputed (bosectl `[numSteps, step, flags]` vs bozo `[step, numSteps, flags]`).
- **Threading.** The shim is single-threaded. Every call happens on `BMAPThread`, and the callback must not re-enter the shim.
  Do not add locks to hide a threading bug.
- C++17, no RTTI-dependent tricks, and no global mutable state other than constant tables.

## Tests

Tests live in `Tests/BMAPShimTests/` (Swift Testing, through the C API). Every deny-list rule is tested in every profile. Every parser is
tested against fixtures plus truncated, oversize and concatenated inputs. A throwing or garbage `BMAPLink` must return a status.
