// Blizzard's own exception types. They never leave the shim: facade.cpp maps each one to a blz_status.
#pragma once

#include <stdexcept>
#include <string>

#include "bmap_shim.h"

namespace blz {

// The allowlist refused an outbound packet.
class denied_error : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

// A reply was missing, truncated or malformed.
class parse_error : public std::runtime_error {
public:
    using std::runtime_error::runtime_error;
};

// The Swift link reported a failure (timeout, closed, busy, connect) or broke its contract.
class link_error : public std::runtime_error {
public:
    link_error(blz_status status, const std::string& message)
        : std::runtime_error(message), status_(status) {}
    blz_status status() const noexcept { return status_; }

private:
    blz_status status_;
};

} // namespace blz
