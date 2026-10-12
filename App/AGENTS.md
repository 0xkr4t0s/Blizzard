# App/: SwiftUI menu bar app

This directory adds to the root AGENTS.md. Design: ARCHITECTURE §3. Requirements: SPEC FR-018, FR-019, FR-020 to FR-024, FR-040 to FR-045.

## Files (planned)

- `BlizzardApp.swift`: `MenuBarExtra { PanelView() }.menuBarExtraStyle(.window)` plus a `Settings` scene.
- `DeviceStore.swift`: `@MainActor @Observable`.
- `Views/`: the panel, mode picker, self-voice control, status banner, settings.
- `Info.plist`: `LSUIElement = YES` and `NSBluetoothAlwaysUsageDescription` (plain wording, e.g. "Blizzard connects to your Bose
  headphones over Bluetooth to show battery and change modes.").
- `Blizzard.entitlements`: App Sandbox (pending T013) and `com.apple.security.device.bluetooth`. Nothing else.

## Rules specific to this directory (override: this target *may* use default-MainActor isolation)

- **Never import IOBluetooth or BMAPShim here.** Use `DeviceSession` (BlizzardCore) only.
- **Never block.** No semaphores and no synchronous waits on the main actor. Long operations show a pending state.
- **Show the device's truth.** After a write, render the value `DeviceSession` returns (the read-back). Never show an optimistic value.
  A pending state is fine.
- **Hide unverified features.** If PROTOCOL.md does not mark a feature Blizzard-verified, there is no control for it. Do not show a
  disabled control "coming soon".
- **Busy state copy:** "Headphones busy: close the Bose app on your phone, then Retry." Retry is manual.
- **Liquid Glass.** Use `GlassEffectContainer` + `glassEffect(_:in:)` only on custom controls (the mode buttons), because the `.window` panel
  is already glass on macOS 26. Gate it with `if #available(macOS 26, *)`, and give it a plain fallback for Reduce Transparency and older macOS.
- **Appearance and accessibility.** Use semantic colours and SF Symbols, which give light/dark for free. Every control needs an accessibility label.
- **Settings and login.** Opening Settings from an `LSUIElement` app needs `NSApp.activate()` first. Launch at login uses `SMAppService.mainApp`;
  handle `.requiresApproval` with a button that calls `SMAppService.openSystemSettingsLoginItems()`.
- **Polling.** Refresh on panel open. While the panel is closed, poll no more often than every 5 min. No timers when disconnected.
- **Previews** use `SimLink`, never real Bluetooth.
- **House style matches Purrifier** (the author's other native menu bar app). Keep the panel compact, one screen, no tabs.
