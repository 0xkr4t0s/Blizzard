#include "allowlist.hpp"

namespace blz {

namespace {

// BMAP operators (docs/PROTOCOL.md §Packet format).
constexpr uint8_t kGet = 1;
constexpr uint8_t kSetGet = 2;
constexpr uint8_t kStart = 5;

struct Function {
    uint8_t fblock;
    uint8_t function;
};

struct Header {
    uint8_t fblock;
    uint8_t function;
    uint8_t op;
    const uint8_t* payload;
    size_t payload_len;
};

// FirmwareUpdate, Debug, Authentication, Cloud: every operator, GET included.
constexpr uint8_t kDeniedBlocks[] = {3, 8, 18, 20};

// Every function PROTOCOL.md marks DENY, for every operator.
constexpr Function kDeniedFunctions[] = {
    {1, 6},                                              // ANR (QC35-style)
    {4, 1}, {4, 2}, {4, 3}, {4, 7}, {4, 8}, {4, 12},     // connect, disconnect, remove, clear list, pairing, routing
    {5, 3},                                              // media keys
    {7, 4}, {7, 5}, {7, 6}, {7, 7}, {7, 11},             // power off, factory default, ship mode, ANR-only, reset
    {31, 9},                                             // mode reset
};

// APP: reads PROTOCOL.md marks `GET`, with an empty payload.
constexpr Function kAppGets[] = {
    {0, 1}, {0, 3}, {0, 5}, {1, 2}, {2, 2}, {31, 3},
};

// PROBE: every function PROTOCOL.md lists with a GET or PROBE policy, with an empty payload.
constexpr Function kProbeGets[] = {
    {0, 1}, {0, 3}, {0, 5}, {0, 6}, {0, 7}, {0, 15},
    {1, 2}, {1, 3}, {1, 4}, {1, 5}, {1, 7}, {1, 9}, {1, 10}, {1, 11}, {1, 16}, {1, 24}, {1, 27}, {1, 29},
    {2, 2}, {2, 5}, {2, 9},
    {4, 4}, {4, 5},
    {5, 1}, {5, 5},
    {31, 2}, {31, 3}, {31, 4}, {31, 8}, {31, 10}, {31, 11},
};

// Gen 1 answers mode indices 0-9 and errors on 10.
constexpr uint8_t kMaxModeIndex = 9;

bool parse_header(const uint8_t* pkt, size_t len, Header& out) noexcept {
    if (pkt == nullptr || len < 4) return false;
    if (pkt[3] != len - 4) return false;
    if ((pkt[2] & 0xF0) != 0) return false;  // device ID and port are 0 for headphones
    out = Header{pkt[0], pkt[1], static_cast<uint8_t>(pkt[2] & 0x0F), pkt + 4, len - 4};
    return true;
}

template <size_t N>
bool contains(const Function (&table)[N], const Header& h) noexcept {
    for (const auto& f : table) {
        if (f.fblock == h.fblock && f.function == h.function) return true;
    }
    return false;
}

bool is(const Header& h, uint8_t fblock, uint8_t function, uint8_t op) noexcept {
    return h.fblock == fblock && h.function == function && h.op == op;
}

bool absolutely_denied(const Header& h) noexcept {
    // Only GET, SETGET and START are commands. SET needs cloud auth; the rest are response operators.
    if (h.op != kGet && h.op != kSetGet && h.op != kStart) return true;
    for (auto block : kDeniedBlocks) {
        if (h.fblock == block) return true;
    }
    if (contains(kDeniedFunctions, h)) return true;
    if (is(h, 1, 5, kSetGet)) return true;  // CNC write: error 5 on gen 1
    return false;
}

bool mode_config_get(const Header& h) noexcept {
    return is(h, 31, 6, kGet) && h.payload_len == 1 && h.payload[0] <= kMaxModeIndex;
}

bool app_allowed(const Header& h) noexcept {
    if (h.op == kGet) {
        return (h.payload_len == 0 && contains(kAppGets, h)) || mode_config_get(h);
    }
    if (is(h, 31, 3, kStart)) {
        return h.payload_len == 2 && h.payload[0] <= kMaxModeIndex && h.payload[1] <= 1;
    }
    if (is(h, 1, 11, kSetGet)) {
        return h.payload_len == 2 && h.payload[0] == 1 && h.payload[1] <= 3;
    }
    return false;
}

bool probe_allowed(const Header& h) noexcept {
    if (h.op != kGet) return false;
    return (h.payload_len == 0 && contains(kProbeGets, h)) || mode_config_get(h);
}

} // namespace

bool packet_allowed(blz_profile profile, const uint8_t* pkt, size_t len) noexcept {
    Header h{};
    if (!parse_header(pkt, len, h)) return false;
    if (absolutely_denied(h)) return false;
    switch (profile) {
        case BLZ_PROFILE_APP:
            return app_allowed(h);
        case BLZ_PROFILE_PROBE:
            return probe_allowed(h);
        case BLZ_PROFILE_REPLAY:
            return true;
        default:
            return false;
    }
}

} // namespace blz
