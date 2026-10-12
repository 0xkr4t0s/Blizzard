# 2. Wrap bosectl's C++ library through a Blizzard-owned C shim

- Status: Accepted
- Date: 2026-10-12

## Context

bosectl (MIT, aaronsb) implements BMAP in Python, Rust and C++. All three share the same layers: codec, Transport, DeviceConfig,
`BmapConnection` and catalog. The C++ library is mostly header-only (only `transport.cpp` and `discovery.cpp` are compiled), is C++17
and CMake ≥ 3.14, and is built and tested on `macos-latest` in CI. It takes an injectable
`bmap::Transport` with just two methods, `send_recv` and `send_recv_drain`. bosectl-qt already embeds it as a submodule.
Constraints:

- Neither library has an FFI surface.
- The C++ API throws exceptions derived from `std::runtime_error`, and Swift cannot catch C++ exceptions. One escaping exception terminates the app.
- Swift C++ interop is "viral": every dependent target must enable it. Reference types also need macOS 13.3+.

Sources: [bosectl architecture.md](https://github.com/aaronsb/bosectl/blob/70570b29c1d3c9ba775b08a29eaea72385de27b5/docs/architecture.md),
[transport.h](https://github.com/aaronsb/bosectl/blob/70570b29c1d3c9ba775b08a29eaea72385de27b5/cpp/src/transport.h),
[Swift interop status](https://swift.org/documentation/cxx-interop/status/),
[Swift build setup](https://www.swift.org/documentation/cxx-interop/project-build-setup/).

## Alternatives

- **Rust `bose-bmap` 0.5.0 via UniFFI, swift-bridge or cbindgen.** Its `Result` errors carry no exception risk. The costs:
  - a second toolchain;
  - an XCFramework or lipo build;
  - a concrete wrapper type for the generic `BmapConnection<T>`;
  - channel probing and init are private and would have to be re-implemented.
- **Pure Swift port.** No bridging at all, but it forks the protocol knowledge and loses upstream parser fixes (e.g. PR #43).
- **Python pybmap via an embedded interpreter or subprocess.** It already works on macOS through PyObjC, but shipping and signing
  an interpreter is heavy and bad for a menu bar app.

## Decision

- Use bosectl's **C++** headers from a git submodule pinned to a reviewed commit, initially `70570b2` (v0.5.0).
  `Vendor/AGENTS.md` records the current pin.
- Wrap them in `Sources/BMAPShim`, a Blizzard-owned C++17 target that contains:
  - `CallbackTransport : bmap::Transport`, which calls Swift through a C function pointer plus a `void*` context;
  - an exception-safe façade where every entry point ends in `catch (...)`;
  - the command allowlist (ADR-0004);
  - the lonestarr `DeviceConfig` and gen-1 parsers.
- Expose the shim to Swift through a **plain C header** (`include/bmap_shim.h`), not C++ interop, so Swift targets stay
  interop-free and the ABI is small enough to audit.
- Compile no vendored `.cpp` and do not include `bmap.h`.

## Consequences

- Upstream codec and parser fixes arrive by bumping the submodule (`/bump-bosectl`).
- Blizzard owns a small amount of C++ (an estimated few hundred lines). Those lines are the security-critical code and are tested through the C API from Swift.
- Value types are copied across a C boundary into caller-provided buffers, so there are no ownership puzzles.
- If the C API grows unwieldy, C++ interop can be revisited in a new ADR.

## Notes

(Append dated submodule bumps here via `/bump-bosectl`.)
