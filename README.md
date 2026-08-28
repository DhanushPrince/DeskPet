# DeskPet

A menu-bar desktop pet for macOS. Native rewrite of the Electron app: Swift,
AppKit, and SwiftUI, no third-party packages. The pet sits on the desktop,
reminds you to take breaks and drink water, and can watch for distracting apps
during focus sessions.

Requires **macOS 14** or later.

## Download

**[Click here to download DeskPet.dmg](https://github.com/DhanushPrince/DeskPet/releases/latest/download/DeskPet.dmg)** — macOS 14 or later.

Open the disk image, drag **DeskPet** into Applications, then launch from there. macOS may ask you to allow the app the first time (ad-hoc signed build); use **System Settings → Privacy & Security → Open Anyway** if needed.

No release yet? Build locally with `make dist` (see below), or check [Releases](https://github.com/DhanushPrince/DeskPet/releases) for uploaded builds.

## Build

Command Line Tools are enough (`xcode-select --install`). Full Xcode is not
required.

```
make test    # Swift Testing suite
make app     # assemble DeskPet.app (ad-hoc, hardened runtime)
make run     # build and launch
make dmg     # wrap the current configuration in DeskPet.dmg
make dist    # release configuration + DMG
make icon    # regenerate Support/AppIcon.icns from docs/app-icon.png
```

The `.app` is assembled by the Makefile from the SwiftPM binary. It is signed
ad-hoc with the hardened runtime (`Support/DeskPet.entitlements`). Gatekeeper
will still show an “unverified developer” prompt until a Developer ID identity
and notarization are available (`make notarize` documents that gap).

## Using the app

DeskPet is a menu-bar accessory (`LSUIElement`): no Dock icon. Open **Settings**
from the paw menu item.

- **Custom pet:** Appearance → Custom Assets. Idle is required; other states are
  optional. GIFs are copied into
  `~/Library/Application Support/DeskPet/custom_pet_assets/`.
- **Launch at login:** System → Launch at Login. Uses `SMAppService`. Ad-hoc
  and unsigned builds often cannot register; the preference is still saved.
- **Updates:** System → Check for Updates, or enable Check Updates on Launch
  (1.5s delay). Reads GitHub Releases at
  `https://github.com/DhanushPrince/DeskPet/releases`.
- **Distraction detection:** Focus card. App-name rules work without
  Accessibility; window-title keywords need it. Grant access in System Settings
  › Privacy & Security › Accessibility. Ad-hoc rebuilds can drop the grant
  because macOS keys it to the code signature.

## Measured size and idle cost

Taken on macOS 26.6 (Apple silicon) from an ad-hoc debug `DeskPet.app` with the
pet visible and Settings open. `sample` rather than Instruments (Command Line
Tools only).

| Metric | Native (measured) | Earlier plan estimate | Electron (plan) |
| --- | --- | --- | --- |
| App bundle | **22 MB** app / **19 MB** DMG | 25–40 MB | 150–200 MB |
| Idle CPU | **~1.1%** (`ps %cpu`, ~13s after launch) | < 1% | Chromium overhead |
| Memory | **47 MB** physical footprint (`sample`); ~95 MB RSS | < 50 MB | 100–200 MB |

RSS is higher than the physical footprint because it includes shared dirty
pages. The pet uses `CAKeyframeAnimation` on decoded GIF frames, not
`NSImageView.animates`.

## Layout

```
Sources/DeskPet/          # executable entry
Sources/DeskPetKit/       # app logic, windows, settings
Tests/DeskPetTests/
Support/Info.plist
Support/AppIcon.icns
Support/DeskPet.entitlements
docs/app-icon.png         # source artwork for the icon
```

Source is MIT (`LICENSE`). Bundled pet GIFs are not; see `ASSET_LICENSE.md`.
