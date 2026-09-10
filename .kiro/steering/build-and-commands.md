---
inclusion: always
---

# Build, run & tooling

Full Xcode is **not** required — Command Line Tools (`xcode-select --install`)
are enough. SwiftPM compiles; the `Makefile` assembles the bundle.

```
make test    # swift test — Swift Testing suite
make app     # assemble DeskPet.app (ad-hoc signed, hardened runtime)
make run     # release build + launch
make run-debug  # debug build with DESKPET_DEBUG_* harness + dev menu items
make dmg     # wrap current config in DeskPet.dmg
make dist    # release configuration + DMG
make icon    # regenerate Support/AppIcon.icns from docs/app-icon.png
make e2e     # app + Scripts/e2e_smoke.sh
```

- Prefer `make` targets over raw `swift build` / `swift test` so the correct
  configuration and bundle assembly are used.
- The `.app` is signed ad-hoc (`codesign --sign -`) with the hardened runtime
  and `Support/DeskPet.entitlements`. A Developer ID identity + notarization
  are not yet available; `make notarize` documents that gap and fails clearly.
- CI (`.github/workflows/ci.yml`) runs `make test` and `make app`, plus Linux
  scanners: `gitleaks`, `mobsfscan --type ios`, `osv-scanner`.

## Package.swift is intentional

- Split into library `DeskPetKit` + thin executable `DeskPet` so the test target
  can link the library (SPM can't reliably test a `@main` executable).
- **Swift 5 language mode on purpose.** AppKit view/window subclasses, CALayer
  callbacks, and `ReminderScheduler` timers are main-thread-confined by
  construction, not by `Sendable` annotation; Swift 6 strict concurrency rejects
  that pattern wholesale. Do not switch to Swift 6 language mode.
- Linked frameworks: `ServiceManagement`, `IOKit`. Pet assets ship via the
  `DeskPet_DeskPetKit.bundle` resource bundle.
