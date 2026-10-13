// Outbound packet allowlist (ADR-0004, docs/PROTOCOL.md, docs/SECURITY.md §BMAP command safety).
//
// The tables in allowlist.cpp must match the "Blizzard policy" column of docs/PROTOCOL.md. If they disagree,
// the code is wrong. Every rule here has a test per profile in Tests/BMAPShimTests/AllowlistTests.swift.
#pragma once

#include <cstddef>
#include <cstdint>

#include "bmap_shim.h"

namespace blz {

// True if `profile` may send `pkt`. Default deny:
// - A malformed header is denied: fewer than 4 bytes, a length byte that is not `len - 4`, or a non-zero
//   device ID / port in the flags byte.
// - The absolute deny-list applies in every profile: operator SET and every response operator; blocks 3, 8, 18
//   and 20; every function PROTOCOL.md marks DENY; SETGET [1.5].
// - APP: the GETs PROTOCOL.md marks `GET`, START [31.3] `[idx 0-9, prompt 0/1]` and SETGET [1.11] `[1, level 0-3]`.
// - PROBE: GET only, on the functions PROTOCOL.md lists in blocks 0, 1, 2, 4, 5 and 31.
// - REPLAY: anything the absolute deny-list does not block. The once-per-run, acknowledged write limit is
//   enforced by blizzard-probe (PLAN T014), not here.
bool packet_allowed(blz_profile profile, const uint8_t* pkt, size_t len) noexcept;

} // namespace blz
