// Implements bmap_shim.h on top of bosectl's BmapConnection.
//
// Rule: no C++ exception leaves this file. Every extern "C" entry that can throw runs its body
// through guarded(), which catches in the order Sources/BMAPShim/AGENTS.md requires.
// Include individual bosectl headers only, never bmap.h (ARCHITECTURE §1).
#include <cstring>
#include <memory>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "bmap_shim.h"
#include "callback_transport.hpp"
#include "errors.hpp"

#include "connection.h"
#include "device.h"
#include "errors.h"
#include "protocol.h"

struct blz_session {
    blz_session(std::unique_ptr<blz::CallbackTransport> t, bmap::DeviceConfig config)
        : transport(t.get()), connection(std::move(t), std::move(config)) {}

    blz::CallbackTransport* transport;  // owned by `connection`
    bmap::BmapConnection connection;
    std::string last_message;
    uint8_t last_device_error = 0;
};

namespace {

void record(blz_session* s, const char* message, uint8_t device_error = 0) noexcept {
    s->last_device_error = device_error;
    try {
        s->last_message = message;
    } catch (...) {
        s->last_message.clear();
    }
}

template <typename Body>
blz_status guarded(blz_session* s, Body&& body) noexcept {
    if (s == nullptr) return BLZ_ERR_INVALID_ARG;
    s->last_message.clear();
    s->last_device_error = 0;
    try {
        body();
        return BLZ_OK;
    } catch (const bmap::busy_error& e) {  // before connect_error, its base
        record(s, e.what());
        return BLZ_ERR_BUSY;
    } catch (const bmap::connect_error& e) {
        record(s, e.what());
        return BLZ_ERR_CONNECT;
    } catch (const bmap::device_error& e) {
        record(s, e.what(), e.code());
        return BLZ_ERR_DEVICE;
    } catch (const bmap::unsupported_error& e) {
        record(s, e.what());
        return BLZ_ERR_UNSUPPORTED;
    } catch (const bmap::desync_error& e) {
        record(s, e.what());
        return BLZ_ERR_DESYNC;
    } catch (const blz::denied_error& e) {
        record(s, e.what());
        return BLZ_ERR_DENIED;
    } catch (const blz::parse_error& e) {
        record(s, e.what());
        return BLZ_ERR_PARSE;
    } catch (const blz::link_error& e) {
        record(s, e.what());
        return e.status();
    } catch (const std::invalid_argument& e) {
        record(s, e.what());
        return BLZ_ERR_INVALID_ARG;
    } catch (const std::exception& e) {
        record(s, e.what());
        return BLZ_ERR_INTERNAL;
    } catch (...) {
        record(s, "unknown exception");
        return BLZ_ERR_INTERNAL;
    }
}

// Sends GET `addr` and returns the matching reply frame. The buffer can also hold unsolicited
// frames; those are skipped. Frames only from other addresses mean the link is out of step.
bmap::BmapResponse get_frame(blz_session* s, bmap::Addr addr) {
    const auto packet = bmap::bmap_packet(addr.fblock, addr.func, bmap::Operator::Get);
    const auto frames = bmap::parse_all_responses(s->transport->send_recv(packet));
    if (frames.empty()) throw blz::parse_error("no BMAP frame in the reply");
    for (const auto& frame : frames) {
        if (frame.fblock != addr.fblock || frame.func != addr.func) continue;
        if (frame.op == bmap::Operator::Error) {
            throw bmap::device_error(frame.fmt(), frame.payload.empty() ? 0 : frame.payload[0]);
        }
        if (frame.op != bmap::Operator::Status) {
            throw blz::parse_error("unexpected reply " + frame.fmt());
        }
        return frame;
    }
    throw bmap::desync_error("reply came from [" + std::to_string(frames[0].fblock) + "." +
                             std::to_string(frames[0].func) + "]");
}

} // namespace

extern "C" {

uint32_t blz_abi_version(void) noexcept {
    return BLZ_ABI_VERSION;
}

blz_session* blz_session_create(blz_send_recv_fn fn, void* ctx, blz_profile profile) noexcept {
    if (fn == nullptr) return nullptr;
    switch (profile) {
        case BLZ_PROFILE_APP:
        case BLZ_PROFILE_PROBE:
        case BLZ_PROFILE_REPLAY:
            break;
        default:
            return nullptr;
    }
    try {
        auto transport = std::make_unique<blz::CallbackTransport>(fn, ctx, profile);
        // Empty config: every typed feature is unsupported until PLAN T020 adds qc_ultra_gen1().
        return new blz_session(std::move(transport), bmap::DeviceConfig{});
    } catch (...) {
        return nullptr;
    }
}

void blz_session_destroy(blz_session* s) noexcept {
    delete s;
}

blz_status blz_init(blz_session* s) noexcept {
    return guarded(s, [&] { get_frame(s, bmap::Addr{0, 1}); });
}

bool blz_packet_allowed(blz_profile profile, const uint8_t* pkt, size_t len) noexcept {
    return blz::packet_allowed(profile, pkt, len);
}

uint8_t blz_last_device_error(const blz_session* s) noexcept {
    return s == nullptr ? 0 : s->last_device_error;
}

size_t blz_last_error_message(const blz_session* s, char* buf, size_t cap) noexcept {
    if (s == nullptr) {
        if (buf != nullptr && cap > 0) buf[0] = '\0';
        return 0;
    }
    const std::string& message = s->last_message;
    if (buf != nullptr && cap > 0) {
        const size_t n = message.size() < cap - 1 ? message.size() : cap - 1;
        std::memcpy(buf, message.data(), n);
        buf[n] = '\0';
    }
    return message.size();
}

} // extern "C"
