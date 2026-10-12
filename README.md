# Blizzard

A native macOS menu bar app for **Bose QuietComfort Ultra Headphones (1st Gen, 2023)**. It shows battery level and
switches listening modes from your Mac, with no phone, account or cloud involved.

> **Status: pre-alpha, in planning.** There is no build yet. The plan, spec and design are in [`docs/`](docs/).

## What it will do

- **v0.1 (M1-M2):** connect, then show battery, firmware, name and the current mode. Switch modes, and set self-voice.
- **Later (M3):** EQ, custom modes, auto-off and rename. Each ships only after it has been verified on gen-1 hardware.
- **Never:** firmware updates, factory reset, anything that needs Bose's cloud authentication, or any network access
  (apart from opt-in update checks, once added).

## How it works

Blizzard wraps the C++ library from **bosectl**, which implements Bose's BMAP protocol, through a small exception-safe C
shim. It supplies its own Swift IOBluetooth RFCOMM transport, because the upstream C++ transport is Linux-only.
Every command passes a default-deny allowlist. See [ARCHITECTURE](docs/ARCHITECTURE.md),
[PROTOCOL](docs/PROTOCOL.md) and [SECURITY](docs/SECURITY.md).

Requirements (planned): macOS 15 or later (Liquid Glass on macOS 26), and paired QC Ultra Headphones (1st Gen).
The minimum macOS version is still open (see SPEC NFR-009).

## Security

See [docs/SECURITY.md](docs/SECURITY.md) for supported versions and private vulnerability reporting.

## Credits

- [aaronsb/bosectl](https://github.com/aaronsb/bosectl): the BMAP library Blizzard wraps (MIT, © 2026 Aaron Bockelie).
  It is included as a git submodule, and its licence applies to that code.
- [NerdySouth/bozo](https://github.com/NerdySouth/bozo): gen-1 protocol notes and a CoreBluetooth implementation (MIT).
- [airvzxf/bose-connect-app-linux](https://github.com/airvzxf/bose-connect-app-linux): hardware-verified gen-1
  commands on firmware 1.6.7.

## Disclaimer

Blizzard is an independent project. It is **not affiliated with, endorsed by, or supported by Bose Corporation**.
"Bose" and "QuietComfort" are trademarks of Bose Corporation. They are used here only to identify compatible hardware.
Blizzard uses only unauthenticated protocol operations that the community has documented. Use it at your own risk.

## Licence

MIT (planned, PLAN T002).
