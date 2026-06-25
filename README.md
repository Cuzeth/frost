# Frost

Frost is a macOS menu-bar input locker. It suppresses keyboard, mouse, and
trackpad input while keeping the display visible, then unlocks with Touch ID or
the normal macOS password fallback.

It is built for the awkward but useful moment when you want the Mac to keep
showing an unattended task, but you do not want local input to interfere with it:
an agent run, a long build, a render, a benchmark, a terminal session, or any
other visible-but-hands-off work.

Frost is best described as:

- an input suppressor
- an overlay manager
- a local authentication gate

It is not a screen locker, not a replacement for the macOS login window, and not
a security boundary against a determined person with physical access. Your
screen contents stay visible.

## Status

Frost is a focused macOS app in active development.

- Platform: macOS 14.6+
- UI: SwiftUI plus AppKit
- App type: `LSUIElement` menu-bar agent, with no Dock icon
- Bundle ID: `dev.abdeen.frost`
- Updates: Sparkle 2.9.3
- Sandbox: off
- Hardened Runtime: on

## What Frost Does

When you choose **Lock Input**, Frost:

1. Checks that Accessibility and Input Monitoring are granted.
2. Creates an active `CGEvent` tap.
3. Suppresses keyboard and pointer events by swallowing them in the tap callback.
4. Freezes the cursor position.
5. Shows a translucent overlay on every display.
6. Hides system switching surfaces that cannot be stopped at the event-tap layer.
7. Optionally holds power assertions to keep the display and/or system awake.
8. Waits for the configured unlock shortcut.

When you press the unlock shortcut, Frost keeps the overlay and event tap active,
then asks macOS to authenticate with `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`.
That gives Touch ID when available and password fallback when needed. If
authentication succeeds, Frost tears everything down and restores normal input.
If it is cancelled or fails, Frost returns to the locked state.

The default unlock shortcut is `Control-Option-Command-U`.

## What Frost Does Not Do

Frost deliberately does not:

- hide, blank, blur, or replace the screen
- log the user out
- switch to the macOS login window
- run as root
- install a kernel extension
- install a privileged helper
- claim to protect against a determined local attacker
- claim closed-lid operation
- send telemetry, analytics, crash reports, licensing calls, or account data

The only intended network activity is Sparkle update checking.

## Safety And Recovery

Input suppression is inherently risky: a bug can leave the local keyboard and
mouse unable to interact with the app. Frost keeps several escape hatches, and
they are part of the project contract.

### Normal Unlock

Press the configured unlock shortcut, then authenticate with Touch ID or the
macOS password fallback.

The unlock shortcut is recognized inside the event-tap callback, because normal
menu and keyboard routing is unavailable while input is suppressed.

### Remote Kill

Frost catches `SIGTERM` and performs a clean teardown before exiting. That
teardown restores the cursor, releases the event tap, releases power assertions,
dismisses overlays, and clears app presentation options.

Because local input is suppressed while locked, the practical recovery route is
from another device over SSH:

```sh
pkill -x frost
```

You can also use `kill <pid>` if you already know the process ID. A terminal
that was opened before locking can also send the signal.

There is intentionally no in-repo kill script. The `SIGTERM` handler is the
recovery contract.

### Debug Auto-Unlock

Debug builds include an automatic unlock timer. In the current code, it fires
after 20 seconds and tears the lock down regardless of authentication state.

This is compiled only in `DEBUG` builds and must never ship in release builds.

### Recovery UI

If Frost cannot acquire the required permissions or cannot create an event tap,
it does not lock input. Instead, it shows an **Input Not Locked** recovery overlay
with guidance and a button to open Privacy settings.

### Force Quit

Frost disables the Force Quit panel while locked. This is intentional: opening
Force Quit while the Touch ID/password prompt is active can steal focus from the
auth prompt and strand the user. Use the unlock shortcut, the debug auto-unlock
in debug builds, or the `SIGTERM` path above.

## Permissions

Frost needs two user-granted macOS privacy permissions:

- Accessibility: required for an active event tap to alter or suppress events.
- Input Monitoring: required to receive keyboard events in the tap.

They are granted in:

```text
System Settings > Privacy & Security
```

If either permission is missing, Frost prompts where macOS allows it, then shows
the recovery overlay instead of suppressing input.

## Settings

Open settings from the menu-bar item. If the menu-bar item is hidden, relaunching
Frost opens the settings window directly.

Current settings:

- Unlock Shortcut: required; defaults to `Control-Option-Command-U`.
- Lock Shortcut: optional global shortcut that starts input suppression.
- Prevent screen saver: holds a display-sleep prevention assertion while locked.
- Prevent sleep: holds an idle system-sleep prevention assertion while locked.
- Show in menu bar: controls whether the menu-bar item is visible.
- Quit Frost: exits the menu-bar agent from the settings window.

The optional lock shortcut uses a global `NSEvent` monitor while Frost is
unlocked. The unlock shortcut is handled separately inside the `CGEvent` tap
while Frost is locked.

## Menu Bar

Frost is an `LSUIElement` agent, so it has no Dock icon. The menu-bar item
contains:

- Lock Input
- Settings...
- Check for Updates...
- Quit Frost

If the menu-bar item is hidden in settings, Frost still needs a way back in.
`AppDelegate` handles launch and reopen events and shows the explicit AppKit
settings window.

## How It Works

### Input Suppression

`EventTapManager` owns the `CGEvent` tap. It prefers a HID-level tap and falls
back to a session-level tap if needed:

- `CGEventTapLocation.cghidEventTap`
- `CGEventTapLocation.cgSessionEventTap`
- `.headInsertEventTap`
- `.defaultTap`

Returning `nil` from the callback swallows input. The callback recognizes the
unlock shortcut before swallowing the key event.

During authentication, the tap remains active and the overlay remains visible.
Bare Escape is allowed through so the system authentication prompt can be
cancelled. Modified Escape combinations, including Force Quit, remain swallowed.

### Overlay

`OverlayCoordinator` creates one borderless `NSWindow` per display.

Overlay windows:

- use `.screenSaver` level
- join all Spaces
- support full-screen auxiliary presentation
- rebuild when screen parameters change
- use a translucent material card so the underlying screen remains visible

The normal locked overlay is informational. Recovery overlays are interactive
only when input was not successfully locked.

### App Presentation Options

Some system gestures and switchers happen above the HID event layer. Frost uses
`NSApplicationPresentationOptions` while locked to hide or disable those routes:

- hide Dock
- hide menu bar
- disable process switching
- disable Force Quit
- disable Apple menu

Those options are always cleared during teardown.

### Local Authentication

`UnlockCoordinator` wraps LocalAuthentication:

```swift
LAContext.evaluatePolicy(.deviceOwnerAuthentication)
```

This asks macOS for device-owner authentication. Depending on the Mac and
current system state, that may be Touch ID, password fallback, or another
standard macOS authentication route.

### Power Assertions

`SleepAssertionManager` uses IOKit power assertions while locked:

- `kIOPMAssertionTypePreventUserIdleDisplaySleep`
- `kIOPMAssertionTypePreventUserIdleSystemSleep`

They are controlled by settings and released on every teardown path. They do not
override the power button or closed-lid behavior.

### Updates

`UpdaterController` owns Sparkle's `SPUStandardUpdaterController`.

Sparkle reads:

- `SUFeedURL` from `frost/Info.plist`
- `SUPublicEDKey` from `frost/Info.plist`

The current feed URL is:

```text
https://updates.abdeen.dev/frost/appcast.xml
```

Do not replace `SUPublicEDKey`. It is the public EdDSA key used to verify
updates for existing installs.

## Source Map

- `frost/frostApp.swift`: app entry point, menu-bar item, shared controllers.
- `frost/AppDelegate.swift`: launch/reopen hooks for showing settings.
- `frost/SettingsWindowController.swift`: explicit AppKit settings window.
- `frost/SettingsView.swift`: settings UI.
- `frost/SettingsStore.swift`: persisted user preferences.
- `frost/LockController.swift`: lock-session state machine and teardown owner.
- `frost/EventTapManager.swift`: active `CGEvent` tap and unlock shortcut handling.
- `frost/OverlayCoordinator.swift`: per-display overlay windows and recovery UI.
- `frost/UnlockCoordinator.swift`: LocalAuthentication wrapper.
- `frost/SleepAssertionManager.swift`: display and system idle assertions.
- `frost/PermissionManager.swift`: Accessibility and Input Monitoring checks.
- `frost/Shortcut.swift`: shortcut persistence, matching, and display.
- `frost/ShortcutRecorder.swift`: AppKit-backed shortcut recorder control.
- `frost/UpdaterController.swift`: Sparkle update wrapper.
- `scripts/publish.sh`: DMG packaging and appcast generation.

## Build From Source

1. Open `frost.xcodeproj` in Xcode.
2. Select the `frost` target/scheme.
3. Build and run.
4. Grant Accessibility and Input Monitoring when prompted.
5. If macOS does not activate the new permissions immediately, relaunch Frost.

Important project settings:

- `MACOSX_DEPLOYMENT_TARGET = 14.6`
- `ENABLE_APP_SANDBOX = NO`
- `ENABLE_HARDENED_RUNTIME = YES`
- `INFOPLIST_KEY_LSUIElement = YES`
- Sparkle is resolved through Swift Package Manager.

For AI agents and automated edits, read `AGENTS.md` before touching the project.
It contains the safety invariants that must not regress.

## Release Packaging

Releases are packaged with:

```sh
scripts/publish.sh /path/to/frost.app
```

The script expects an already exported, signed, notarized, and stapled
`frost.app`. It does not build, sign, notarize, or staple the app.

The script:

1. Reads the version from the exported app's `Info.plist`.
2. Creates `dist/Frost-<version>.dmg`.
3. Runs Sparkle's `generate_appcast`.
4. Writes `dist/appcast.xml`.

Upload both files to:

```text
https://updates.abdeen.dev/frost/
```

Sparkle's private EdDSA key belongs in the developer's login Keychain, created
by Sparkle's `generate_keys`. It must not be committed or written into this
repository.

## Development Rules Worth Keeping Visible

- Preserve the `SIGTERM` teardown path.
- Preserve the debug auto-unlock timer in debug builds only.
- Never start suppressing input without a visible recovery path for startup
  failures.
- Always release the event tap, restore the cursor, clear presentation options,
  and release power assertions during teardown.
- Keep the app non-sandboxed.
- Keep Hardened Runtime enabled.
- Do not add telemetry, analytics, crash reporting, licensing, accounts, or
  network access outside Sparkle update checks.
- Do not introduce root helpers, privileged daemons, or kernel extensions.
- Do not overwrite Sparkle's `SUPublicEDKey`.
- Do not describe Frost as a screen locker or security product.

## Current Gaps

- Launch at login is not implemented yet.
- Notched-display safe-area handling is still called out as TODO in the overlay
  coordinator.
- There is no test target in the current project.
