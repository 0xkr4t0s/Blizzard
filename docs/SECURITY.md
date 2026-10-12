# Security policy

## Supported versions

Blizzard is **pre-alpha**, and no release has been published yet. Until v0.1.0, only the `main` branch is supported.
After that, only the latest release will get security fixes.

| Version | Supported |
|---|---|
| `main` | yes |
| any release < latest | no |

## Reporting a vulnerability

Please report privately through **GitHub private vulnerability reporting**: open the repository's
**Security** tab and choose **Report a vulnerability**. (The maintainer enables this in repo settings, PLAN T017.)
Do not open a public issue for a vulnerability.

- We aim to acknowledge within 7 days and to agree a disclosure date with you, 90 days by default.
- **In scope:**
  - the app sends a BMAP command outside the allowlist below;
  - memory-safety or logic bugs in parsing data from a Bluetooth device;
  - privilege or entitlement misuse;
  - leaking MAC addresses or serials;
  - the update channel (once Sparkle exists);
  - supply-chain issues in pinned dependencies.
- **Out of scope:** bugs in Bose firmware or the Bose app. Report those to Bose. For bugs in bosectl itself, report
  upstream at https://github.com/aaronsb/bosectl.

## Threat model (brief)

- **Assets:**
  - the user's headphones (configuration, and availability: never leave them in a state the user can't undo);
  - the user's Mac (the app runs with Bluetooth access);
  - identifiers (MAC addresses, serial, paired-device list);
  - release signing keys.
- **Untrusted inputs:**
  - **Every byte from the headset.** A spoofed or malicious Bluetooth device can answer BMAP with crafted
    payloads, so treat it like a network peer.
  - Fixture files and captures.
  - The vendored library at each bump.
  - The update feed (later).
- **Adversaries:**
  - a malicious nearby or paired device;
  - a compromised upstream dependency;
  - a careless change, including one by a coding agent, that widens the command surface.

## Legal and ethical position

Blizzard uses only the BMAP operators that work **without authentication**: GET, plus SETGET and START on specific
functions. bosectl, airvzxf/bose-connect-app-linux and NerdySouth/bozo documented these by observing devices
and the public Android app.

Blizzard does **not**:
- touch the Authentication block (18) or Bose's cloud-mediated ECDH flow;
- extract keys, bypass certificate pinning, or impersonate the Bose app or cloud;
- modify firmware.

bosectl describes the same approach: "No keys are extracted, no encryption is broken, no traffic is replayed"
([bosectl README](https://github.com/aaronsb/bosectl/blob/main/README.md)).
Blizzard is an independent interoperability project and is not affiliated with or endorsed by Bose. This section is a statement of intent, not legal advice.

## Rules for coding agents

Each rule names what enforces it:

- `[code allowlist]`: the shim's allowlist/deny-list or the Swift `DenyList`.
- `[test]`: a unit or CI check fails.
- `[settings.json]`: a Claude Code permission deny rule.
- `[review]`: a human or subagent checks it in PR review.
- `[convention-only]`: nothing automated. Follow it anyway.

The full address policy is in `docs/PROTOCOL.md`.

### BMAP command safety

1. **NEVER** send operator **SET (0)** on any address. `[code allowlist]` `[test]`
2. **NEVER** send any operator, GET included, to block **3** (FirmwareUpdate), **8** (Debug), **18** (Authentication)
   or **20** (0x14, Cloud). `[code allowlist]` `[test]`
3. **NEVER** send [7.5] factory default, [7.6] ship mode, [7.7] ANR-only, [7.11] reset or [31.9] mode reset.
   There is no confirmation path; they are not implemented. `[code allowlist]` `[test]`
4. **NEVER** send [7.4] power off, [4.3] remove device or [4.7] clear device list unless *both* of these hold:
   - a new ADR adds the feature;
   - the user confirms in the UI for that single call, enforced by a per-call confirmation flag that the
     allowlist checks.

   Today all three are denied. `[code allowlist]` `[review]`
5. **START** only on allowlisted functions. Today that is only [31.3], with payload `[idx 0-9, prompt 0/1]`. Never fuzz
   or "try" a START on an unknown function: some starts act immediately (for example [7.4] turns the headset off).
   `[code allowlist]` `[test]`
6. **SETGET** only on allowlisted addresses with payloads that match captures. Today that is only [1.11] `[1, level 0-3]`.
   A new write needs a Blizzard-verified PROTOCOL.md row (`/verify-bmap-feature`) and a fixture.
   `[code allowlist]` `[test]` `[review]`
7. **MUST** read back after every write (GET, or the STATUS reply where GET is unverified) and show the device's value,
   not the requested one. Gen 1 silently clamps some values. `[test]`
8. **MUST NOT** write to preset modes. Custom-mode writes go to editable slots only. `[code allowlist]` `[test]`
9. **MUST NOT** expose `send_raw()` or any generic "send bytes" API to Swift in the app. Arbitrary packets are allowed only in
   `blizzard-probe` under the PROBE profile (GET only) and the REPLAY profile. REPLAY requires
   `--i-understand`, a capture reference, and still obeys rules 1-4. `[code allowlist]` `[review]`
10. **MUST NOT** open RFCOMM channels other than the BMAP channel (2, falling back to 8 and 9). Channel 22 is a diagnostic stream.
    `[test]` (Discovery tests) `[review]`

### Untrusted device input

11. **MUST** bounds-check every length and offset before reading a payload, so no read goes past `len`. Treat the
    length byte, string lengths and slot indices as hostile. `[test]` (M4 adds fuzzing, T073)
12. **MUST** cap receive buffers and drain time (64 KiB, 5 s). A device that never stops talking must not exhaust memory.
    `[code allowlist]` `[test]`
13. **MUST NOT** let a C++ exception reach Swift: every `extern "C"` function ends in `catch (...)`. `[test]` `[review]`

### Network, secrets, privacy

14. **MUST NOT** add network code: no `URLSession`, `Network.framework`, sockets, analytics or crash-upload SDKs, and no
    `com.apple.security.network.client` entitlement. The only planned exception is Sparkle, after its ADR (PLAN T077).
    `[test]` (CI grep, T016) `[review]`
15. **NEVER** read, print or commit secrets: `.env*`, `secrets/**`, `*.p12`, `*.p8`, or the Sparkle EdDSA private key
    (it lives in the login Keychain; if exported, only under `secrets/`). `[settings.json]` `[convention-only]` for other agents
16. **MUST** log MAC addresses and serials only with `os_log` privacy `.private`. Committed fixtures must be scrubbed. Never
    commit raw PacketLogger or btsnoop files: they contain every device's traffic. `[test]` (scrub test) `[review]`

### Supply chain and build

17. **NEVER** edit files under `Vendor/bosectl/`. Fix it upstream. A local patch is allowed only under `Vendor/patches/` with
    an ADR, and is applied at build time. `[settings.json]` `[test]` (CI checks the submodule is clean)
18. **MUST** pin every dependency exactly: the submodule to a commit, SwiftPM packages to an exact version, and the CI action
    versions. Bump only via `/bump-bosectl` or an equivalent reviewed PR. `[review]`
19. **MUST** keep entitlements minimal: Hardened Runtime, `com.apple.security.device.bluetooth`, App Sandbox
    (pending T013), and nothing else. **NEVER** add `com.apple.security.cs.disable-library-validation` outside Debug.
    `[review]`
20. **MUST NOT** weaken, skip or delete a test to make a build pass. **MUST NOT** change this section without an ADR.
    `[review]`
