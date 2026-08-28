# DeskPet Native — Tasks

Native macOS rewrite of DeskPet (Swift + AppKit + SwiftUI, zero external
dependencies, SPM + Makefile, macOS 14 minimum). All 18 tasks are done;
`make test` currently passes 389 tests.

## Status

- [x] 1. Scaffold repo and build system
- [x] 2. Port assets and appearance manifest system
- [x] 3. GIF decoding
- [x] 4. Display geometry and positioning logic (pure)
- [x] 5. Transparent floating pet window with animation
- [x] 6. Click-through
- [x] 7. Drag, click, and facing
- [x] 8. Pet state machine
- [x] 9. Persistence and migration
- [x] 10. Menu bar and AppState wiring
- [x] 11. Wall-clock reminder scheduler
- [x] 12. Speech bubble
- [x] 13. Break reminders and break run
- [x] 14. Hydration, focus mode, and stats
- [x] 15. SwiftUI settings window
- [x] 16. Distraction detection
- [x] 17. Custom assets, login item, and updates
- [x] 18. Packaging and release

---

## Task 16 — Distraction detection

Native accessibility-based distraction detection.

**Done and verified:**
- `DistractionClassifier` (ported `classifyDistraction`: case-insensitive app +
  keyword matching, `app:`/`keyword:` prefixes stripped for display, ignores the
  pet's own app), 60s warning cooldown, grace period before the first check.
- `ActiveWindowReader` using `NSWorkspace.frontmostApplication` + `AXUIElement`
  (`kAXFocusedWindowAttribute` → `kAXTitleAttribute`), replacing the osascript
  subprocess (ADR-3).
- `DistractionDetector` (3s poll), wired to `AppState.triggerFocusWarning(rule:)`.
- `DistractionStatus` states (idle / watching / permission-needed / error) with a
  permission-guidance row and "Request Permission" / "Open Privacy Settings"
  buttons in the settings Focus card.
- Ported `distraction.test.ts` plus cooldown, grace, and permission tests.
- **Graceful degradation verified live:** with `AXIsProcessTrusted=false`, the
  detector still read the frontmost app via `NSWorkspace` and matched an app
  rule, reporting `permissionNeeded` with "Blocked apps are still detected".
  App-rule detection needs no permission; only title-keyword matching does.
- **Settings row live-checked:** launching with `DESKPET_DEBUG_SETTINGS` and
  `DESKPET_DEBUG_DISTRACTION` opened Settings and logged
  `status state=watching` with `AXIsProcessTrusted=true`. Pixel screenshot of
  the Focus card could not be taken in this environment (`screencapture`:
  "could not create image from display"). The row uses the same
  SettingsCard/Button path as Task 15; a host-window test covers enabling
  detection.

**Known risk:** unsigned/ad-hoc dev builds lose Accessibility trust on every
rebuild because macOS ties the grant to the code signature. The Makefile
ad-hoc-signs with the hardened runtime; a Developer ID identity would make the
grant stick.

---

## Task 17 — Custom assets, login item, and updates

- [x] **Custom GIF import**: `NSOpenPanel` filtered to `.gif` → sanitize filename
  with `[^a-zA-Z0-9._-]+` → `-` → copy into
  `custom_pet_assets/<state>/<state>-<timestamp>-<safeName>`.
  Path-traversal validation rejects `.` / `..` segments; `PetAssetLoader`
  refuses URLs that escape the custom root.
- [x] **Per-state custom appearance** with `idle` required
  (`PetAppearances.requiredCustomStates`). Custom pet editor UI in settings.
- [x] **Launch at login** via `SMAppService.mainApp` (`LoginItemService`).
  Packaged `.app` builds register/unregister; unpackaged binaries only save
  the preference.
- [x] **Update checker** (`GitHubUpdateChecker` + `Versions.compare`) against
  GitHub Releases. Update-available bubble (`BubbleID.updateAvailable`, 12s),
  `checkUpdatesOnLaunchEnabled` with a 1.5s delay.
- [x] Tests: version comparison, payload parse, path traversal, non-GIF
  rejection, idle required, update bubble wiring.

---

## Task 18 — Packaging and release

- [x] App icon (`.icns` from `docs/app-icon.png`, paw matching the menu bar).
- [x] Makefile `dist` / `dmg` producing an ad-hoc hardened-runtime `.app` and a
  `.dmg`.
- [x] Hardened runtime entitlements (`Support/DeskPet.entitlements`).
- [x] `make notarize` fails clearly without `notarytool` / credentials.
- [x] GitHub Actions: `make test` and `make app`.
- [x] README documenting the build.
- [x] CPU/memory measured with `ps` / `sample` (see README). Bundle **22 MB**,
  physical footprint **~47 MB**, idle CPU **~1%**.

**Known blockers (environment):**
- Only Command Line Tools are installed, not full Xcode, so `xcrun notarytool`
  and Instruments are unavailable. Notarization ends at an ad-hoc-signed DMG
  (same "unverified developer" prompt as the current Electron release).
- Notarization proper requires an Apple Developer account + credentials in CI.

---

## Build

```
make test    # run the test suite
make app     # assemble DeskPet.app
make run     # build + launch
make dmg     # disk image
make dist    # release configuration + DMG
```
