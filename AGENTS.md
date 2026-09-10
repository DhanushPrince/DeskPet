# AGENTS.md

Guidance for AI agents working in the DeskPet repository.

## What this is

DeskPet is a menu-bar desktop pet for **macOS 14+**. It is a native rewrite of
an Electron app in **Swift + AppKit + SwiftUI**. It reminds the user to take
breaks and drink water, runs focus sessions, and can warn about distracting
apps/windows during focus.

- Menu-bar accessory (`LSUIElement` / `.accessory` activation policy): no Dock
  icon, but windows can still be shown and focused.
- Bundle id: `com.dhanushprince.deskpet`.
- Distributed as an ad-hoc signed, hardened-runtime `.app` inside `DeskPet.dmg`.
- **No third-party SPM packages. No Xcode project.** SwiftPM builds the binary;
  a `Makefile` assembles the `.app`.

## Layout

```
Sources/DeskPet/main.swift   # thin executable; calls DeskPetApp.main() only
Sources/DeskPetKit/          # ALL app logic lives here (tests link this library)
  App/        # DeskPetApp, AppDelegate, AppState (composition root)
  Core/       # pure types: settings, persistence, geometry, GIF decode, clock, constants, strings, migration
  Pet/        # PetStateMachine (pure), animator, variant selector, drag math
  Window/     # pet window, content/speech-bubble views, coordinate bridges
  MenuBar/    # status item, menu descriptors and dispatch
  Settings/   # SwiftUI settings view hosted in an AppKit window
  Features/   # schedulers, break run, distraction detection, updates, etc.
  Resources/PetAssets   # bundled GIFs (SPM resource bundle)
Tests/DeskPetTests/      # Swift Testing suite
Support/                 # Info.plist, DeskPet.entitlements, AppIcon.icns
docs/app-icon.png        # source artwork for the icon
Package.swift            # targets + Swift 5 language mode
```

## Composition

- `AppDelegate` owns the process / `NSApplication` lifetime.
- `AppState` is the composition root — an `@Observable` on the main actor.
- `PetStateMachine` is **pure**: no timers, windows, or I/O.
- Features (reminder scheduler, break run, distraction detector, update
  checker) *report*; `AppState` applies the side effects.

## Build & commands

Full Xcode is **not** required — Command Line Tools (`xcode-select --install`)
are enough. Prefer `make` targets over raw `swift build` / `swift test` so the
correct configuration and bundle assembly are used.

```
make test       # swift test — Swift Testing suite
make app        # assemble DeskPet.app (ad-hoc signed, hardened runtime)
make run        # release build + launch
make run-debug  # debug build with DESKPET_DEBUG_* harness + dev menu items
make dmg        # wrap current config in DeskPet.dmg
make dist       # release configuration + DMG
make icon       # regenerate Support/AppIcon.icns from docs/app-icon.png
make e2e        # app + Scripts/e2e_smoke.sh
```

Always run `make test` (and `make app` for bundle-affecting changes) to verify
after a change.

## Package.swift is intentional

- Split into library `DeskPetKit` + thin executable `DeskPet` so the test
  target can link the library (SPM can't reliably test a `@main` executable).
- **Swift 5 language mode on purpose.** AppKit view/window subclasses, CALayer
  callbacks, and `ReminderScheduler` timers are main-thread-confined by
  construction, not by `Sendable` annotation; Swift 6 strict concurrency
  rejects that pattern wholesale. **Do not switch to Swift 6 language mode.**
- Linked frameworks: `ServiceManagement`, `IOKit`. Pet assets ship via the
  `DeskPet_DeskPetKit.bundle` resource bundle.

## Hard rules — do NOT

- Add SPM dependencies or introduce an Xcode project.
- Put logic only in the `DeskPet` executable target (it must stay testable in
  `DeskPetKit`).
- Switch to Swift 6 language mode.
- Steal keyboard focus: `PetWindow.canBecomeKey == false`; show windows with
  `orderFrontRegardless`.
- Change persisted JSON keys or `PetState` raw values (breaks Electron
  migration).
- Use Cocoa coordinates in geometry math (see `.kiro/steering/windows-and-coords.md`).
- Let Quit skip window teardown — `NSApp.terminate` stalls on borderless +
  status-item windows unless windows are torn down first.

## Release / DMG version-bump checklist

So **Check for Updates** works, follow this order when cutting a GitHub release
(`vX.Y.Z`) or shipping `DeskPet.dmg`:

1. **Bump the version first** in `Support/Info.plist`:
   - `CFBundleShortVersionString` → `X.Y.Z`
   - `CFBundleVersion` → next integer
2. Update `Tests/DeskPetTests/BundleSmokeTests.swift` to expect the new short
   version.
3. Commit + push the bump **before** building the DMG.
4. Build: `make test && make dist`
5. Verify the built bundle:
   ```bash
   plutil -p DeskPet.app/Contents/Info.plist | grep -E 'CFBundleShortVersionString|CFBundleVersion'
   ```
6. Tag the **bump commit** (not an older feature commit):
   ```bash
   git tag -f vX.Y.Z
   git push --force origin vX.Y.Z
   ```
7. Upload: `gh release upload vX.Y.Z DeskPet.dmg --clobber`.

**Never** tag or upload a DMG while `Info.plist` still has the previous version
— Check for Updates fails with "The downloaded app is not newer".

## Git authorship (strict)

- Author and committer must be **DhanushPrince** `<r.dhanush307@gmail.com>`.
- **Never** add a `Co-authored-by:` trailer for any AI/agent tool, and never set
  the author/committer to an agent identity.
- Leave git config unchanged.
- Only create commits when explicitly asked. Do not push directly to `main`
  unless explicitly asked.
- After any commit, verify the message with `git log -1 --format='%B'` before
  pushing; strip any agent trailer before pushing.

## Security scanners (CI mirrors)

CI runs three scanners on Linux; local mirrors:

```
gitleaks detect --source .
mobsfscan --type ios Sources Support
osv-scanner scan source --recursive .
```
