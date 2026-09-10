---
inclusion: fileMatch
fileMatchPattern: "Sources/DeskPetKit/{Window,App,Settings}/**/*.swift"
---

# Windows & coordinate spaces

## Coordinate model

- **Global space** (matches Electron): origin at the **top-left of the primary
  display, y increasing downward**. All positioning math uses `GlobalRect` /
  `DisplayGeometry`.
- Convert to Cocoa coordinates **exactly once**, at `ScreenBridge` /
  `CoordinateSpace`, before setting `NSWindow.frame`. Never mix Cocoa coords
  into geometry math.
- **Primary display** = the screen whose Cocoa `frame.origin == .zero`, **not**
  `NSScreen.main`.
- `jsRound` reproduces JavaScript `Math.round` (rounds half toward +∞). Do not
  replace it with Swift `rounded()`.

## Pet window

Borderless, clear background, `.floating` level, `canJoinAllSpaces` +
`fullScreenAuxiliary`, `ignoresMouseEvents` until the hitbox,
`isReleasedWhenClosed = false`, `canBecomeKey == false` (never take focus; show
with `orderFrontRegardless`). Override `performClose` to call `close()` — AppKit
otherwise no-ops and **Quit hangs**.

## Settings window

AppKit `NSWindow` + `NSHostingView` (no SwiftUI `Window` scene).
`applicationShouldTerminateAfterLastWindowClosed` → `false`. Pin
`NSAppearance.aqua` (the cream palette).

## Quit sequence

`prepareToQuit` must: stop `AppState`, hide the pet, close settings, remove the
status item, close remaining windows, **then** `terminate`. Skipping teardown
stalls `NSApp.terminate` on borderless + status-item windows.
