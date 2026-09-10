---
inclusion: fileMatch
fileMatchPattern: "Tests/**/*.swift"
---

# Tests

Use **Swift Testing** (`import Testing`), not XCTest. `@testable import DeskPetKit`.

- **Pure logic tests**: no AppKit; inject `TestClock`; name the Electron behavior
  in the test title.
- **AppKit / `@Observable` / window tests**: mark `@MainActor` and often
  `@Suite(..., .serialized)`.
- Prefer `#expect` / `#require`.
- Ported tests keep their original cases (including JS-rounding cases and the
  "Electron" entry on the distraction ignore list).
- The default suite must **not** require full Xcode or Accessibility permission.
- Window tests that need a display guard with
  `try #require(!NSScreen.screens.isEmpty)`.
- When bumping the app version, update `BundleSmokeTests.swift` to expect the new
  short version (see `releases.md`).

```swift
@Test("a scheduled break is suppressed during focus")
func scheduledBreakSuppressedByFocus() {
    let clock = TestClock()
    let machine = PetStateMachine(clock: clock)
    machine.startFocus()
    #expect(machine.triggerBreakReminder() == false)
}
```
