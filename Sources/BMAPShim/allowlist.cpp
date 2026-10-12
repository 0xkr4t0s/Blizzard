#include "allowlist.hpp"

namespace blz {

namespace {

constexpr uint8_t kOperatorGet = 1;

} // namespace

bool packet_allowed(blz_profile profile, const uint8_t* pkt, size_t len) noexcept {
    switch (profile) {
        case BLZ_PROFILE_APP:
        case BLZ_PROFILE_PROBE:
        case BLZ_PROFILE_REPLAY:
            break;
        default:
            return false;
    }
    if (pkt == nullptr || len < 4) return false;
    // Header: fblock, function, operator (low nibble), payload length.
    if (pkt[3] != len - 4) return false;
    const uint8_t fblock = pkt[0];
    const uint8_t function = pkt[1];
    const uint8_t op = pkt[2] & 0x0F;
    return fblock == 0 && function == 1 && op == kOperatorGet && len == 4;
}

} // namespace blz
