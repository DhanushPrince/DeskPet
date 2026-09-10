---
inclusion: fileMatch
fileMatchPattern: "Sources/**/*.swift"
---

# Swift conventions (DeskPetKit)

- Port Electron behavior faithfully. Keep magic numbers in `Constants`;
  keep user-facing copy in `Strings`.
- Inject time via `DeskPetClock` (e.g. `SystemClock`); tests pass `TestClock`.
  Do not read wall-clock time directly in logic types.
- **Settings** are `Codable` using the Electron **camelCase** keys
  (`petAppearanceId`, etc.). Decode with defaults; run `normalized()` on
  read/write. Never rename or drop persisted keys.
- **Persistence**: `UserDefaults` for settings/position; `stats.json` under
  Application Support (ADR-4).
- **Login item**: `SMAppService.mainApp`, only when
  `Bundle.main.bundlePath.hasSuffix(".app")`. Unpackaged binaries just save the
  preference.
- **Menus**: descriptors in `MenuBuilder`, AppKit assembly in
  `MenuBuilder.makeMenu`, dispatch `MenuAction` through `AppState.handle`.
- **Debug**: gate developer hooks behind `DESKPET_DEBUG_*` env vars in
  `DebugHarness`, inside `#if DEBUG` only.
- Keep types `Sendable` / `Equatable` where they already are. Prefer `enum`
  namespaces (`DisplayGeometry`, `LoginItemService`) over singleton classes.

```swift
// BAD — logic in the DeskPet executable, or a new package dependency
.dependencies: [.package(url: "...")]

// GOOD — testable type in DeskPetKit, clock injected
public init(clock: DeskPetClock = SystemClock()) { self.clock = clock }
```
