# 6. Distribute with Developer ID and notarisation, not the Mac App Store (initially)

- Status: Accepted. Sandbox compatibility is pending spike T013, and the result will be appended under Notes.
- Date: 2026-10-12

## Context

- **App Store review is inconsistent for Bluetooth apps.** One Bluetooth app was rejected for lacking
  `com.apple.security.network.client` even though `com.apple.security.device.bluetooth` was set. That would contradict
  Blizzard's no-network posture.
- **No precedent.** No primary source confirms recent App Store acceptance of an IOBluetooth RFCOMM utility.
- **Signing requirements.** Notarisation requires the Hardened Runtime. Sparkle 2 needs Developer ID (or Apple Development)
  signing; ad-hoc signing can fail to load its framework.
- **House style.** Blizzard follows the author's other app, Purrifier, which is a native Swift menu bar app and open source.

Sources: [com.apple.security.device.bluetooth](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.bluetooth.md),
[Apple Forums 769362](https://developer.apple.com/forums/thread/769362), [Sparkle docs](https://sparkle-project.github.io/documentation/).

## Decision

- **Signing and packaging.** Ship Developer ID-signed builds with the Hardened Runtime, notarised with
  `xcrun notarytool submit --wait`, stapled, as a DMG (also notarised and stapled).
- **Entitlements and Info.plist:**
  - `com.apple.security.device.bluetooth`;
  - App Sandbox **on** as defence in depth, provided T013 shows RFCOMM works sandboxed;
  - no network entitlement;
  - Info.plist: `NSBluetoothAlwaysUsageDescription` and `LSUIElement = YES`.
- **Updates (later).** Sparkle 2 with EdDSA-signed appcasts, after its own ADR (PLAN T077), because it introduces the only network access.
- **Homebrew.** A cask in our own tap.
- **Keys.** Signing identities and the Sparkle private key never enter the repo (SECURITY.md rule 15).

## Consequences

- No App Review dependency, and Sparkle and Homebrew are both possible.
- Users must trust a Developer ID. Notarisation and reproducible release notes help.
- The release procedure is manual at first (`/release`). CI signing on tags only, with a temporary keychain and an App Store Connect API key for notarytool, comes later.
- If T013 shows the sandbox breaks RFCOMM, ship unsandboxed with the Hardened Runtime and record it here.
- A Mac App Store build can be revisited later through a new ADR.

## Notes

(Append dated results: T013 sandbox, TCC prompt behaviour.)
