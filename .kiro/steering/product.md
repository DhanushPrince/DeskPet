---
inclusion: always
---

# DeskPet — product & architecture

Menu-bar desktop pet for **macOS 14+**. Native rewrite of the Electron app in
**Swift + AppKit + SwiftUI**. **No third-party SPM packages. No Xcode project** —
SwiftPM builds the binary, a `Makefile` assembles the `.app`.

The pet sits on the desktop, reminds the user to take breaks and drink water,
runs focus sessions, and can warn about distracting apps/windows during focus.
It is a menu-bar accessory (`LSUIElement` / `.accessory` activation policy): no
Dock icon, but windows can still be shown and focused.

Bundle id: `com.dhanushprince.deskpet`. Distributed as an ad-hoc signed,
hardened-runtime `.app` inside `DeskPet.dmg`.

## Layout

- `Sources/DeskPet/main.swift` — thin executable; calls `DeskPetApp.main()` only.
- `Sources/DeskPetKit/` — **all logic lives here** (tests link this library;
  SPM cannot reliably test a `@main` executable target).
  - `App/` — `DeskPetApp`, `AppDelegate`, `AppState` (composition root).
  - `Core/` — pure types: settings, persistence, geometry, GIF decoding, clock,
    constants, strings, migration.
  - `Pet/` — `PetStateMachine` (pure), animator, variant selector, drag math.
  - `Window/` — pet window, content/speech-bubble views, coordinate bridges.
  - `MenuBar/` — status item, menu descriptors and dispatch.
  - `Settings/` — SwiftUI settings view hosted in an AppKit window.
  - `Features/` — schedulers, break run, distraction detection, updates, etc.
  - `Resources/PetAssets` — bundled GIFs (copied as an SPM resource bundle).
- `Tests/DeskPetTests/` — Swift Testing suite.
- `Support/` — `Info.plist`, `DeskPet.entitlements`, `AppIcon.icns`.
- `Package.swift` — targets + **Swift 5 language mode** (see below).

## Composition

- `AppDelegate` owns the process/`NSApplication` lifetime.
- `AppState` is the composition root, an `@Observable` on the main actor.
- `PetStateMachine` is **pure** — no timers, windows, or I/O.
- Features (reminder scheduler, break run, distraction detector, update checker)
  *report*; `AppState` applies the side effects.

## Hard rules — do not

- Add SPM dependencies or introduce an Xcode project.
- Put logic only in the `DeskPet` executable target (it must stay testable in
  `DeskPetKit`).
- Steal keyboard focus: `PetWindow.canBecomeKey == false`; show windows with
  `orderFrontRegardless`.
- Change persisted JSON keys or `PetState` raw values (breaks Electron
  migration).
- Use Cocoa coordinates in geometry math (see `windows-and-coords.md`).
- Let Quit skip window teardown — `NSApp.terminate` stalls on borderless +
  status-item windows unless windows are torn down first.
