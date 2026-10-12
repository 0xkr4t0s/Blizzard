// Outbound packet allowlist (ADR-0004, docs/PROTOCOL.md, docs/SECURITY.md §BMAP command safety).
#pragma once

#include <cstddef>
#include <cstdint>

#include "bmap_shim.h"

namespace blz {

// True if `profile` may send `pkt`. A malformed header is denied.
//
// Placeholder until PLAN T006: every profile may send exactly GET [0.1] with no payload
// (`00 01 01 00`, CONFIRMED-GEN1), and nothing else. T006 replaces this with the
// APP / PROBE / REPLAY tables and the absolute deny-list.
bool packet_allowed(blz_profile profile, const uint8_t* pkt, size_t len) noexcept;

} // namespace blz
