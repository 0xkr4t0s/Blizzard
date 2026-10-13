// bmap::Transport that sends through the Swift link's C callback.
//
// Every outbound packet, including the ones bosectl builds internally, passes the allowlist here first.
// Swift cannot subclass C++, so this class lives in the shim (ARCHITECTURE §3).
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "allowlist.hpp"
#include "bmap_shim.h"
#include "errors.hpp"
#include "transport.h"

namespace blz {

// Largest reply accepted from the link, matching the link's own drain cap.
inline constexpr size_t kMaxReplyBytes = 64 * 1024;

class CallbackTransport final : public bmap::Transport {
public:
    CallbackTransport(blz_send_recv_fn fn, void* ctx, blz_profile profile)
        : fn_(fn), ctx_(ctx), profile_(profile) {}

    std::vector<uint8_t> send_recv(const std::vector<uint8_t>& packet) override {
        return exchange(packet, false);
    }

    std::vector<uint8_t> send_recv_drain(const std::vector<uint8_t>& packet) override {
        return exchange(packet, true);
    }

private:
    std::vector<uint8_t> exchange(const std::vector<uint8_t>& packet, bool drain) {
        if (!packet_allowed(profile_, packet.data(), packet.size())) {
            throw denied_error("allowlist denied " + describe(packet));
        }
        std::vector<uint8_t> reply(kMaxReplyBytes);
        size_t reply_len = 0;
        const blz_status status =
            fn_(ctx_, packet.data(), packet.size(), drain, reply.data(), reply.size(), &reply_len);
        switch (status) {
            case BLZ_OK:
                break;
            case BLZ_ERR_CONNECT:
            case BLZ_ERR_BUSY:
            case BLZ_ERR_TIMEOUT:
            case BLZ_ERR_CLOSED:
                throw link_error(status, "link failed on " + describe(packet));
            default:
                throw link_error(BLZ_ERR_INTERNAL,
                                 "link returned unexpected status " + std::to_string(status));
        }
        if (reply_len > reply.size()) {
            throw link_error(BLZ_ERR_INTERNAL, "link reported " + std::to_string(reply_len) +
                                                   " bytes into a " + std::to_string(reply.size()) +
                                                   "-byte buffer");
        }
        reply.resize(reply_len);
        return reply;
    }

    // "[fblock.function] op N" for error messages. Never includes payload bytes.
    static std::string describe(const std::vector<uint8_t>& packet) {
        if (packet.size() < 4) return "malformed packet (" + std::to_string(packet.size()) + " bytes)";
        return "[" + std::to_string(packet[0]) + "." + std::to_string(packet[1]) + "] op " +
               std::to_string(packet[2] & 0x0F);
    }

    blz_send_recv_fn fn_;
    void* ctx_;
    blz_profile profile_;
};

} // namespace blz
