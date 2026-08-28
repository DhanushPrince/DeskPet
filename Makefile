# DeskPet — native macOS build
#
# No Xcode project. SPM compiles the binary; this Makefile assembles the
# .app bundle by hand.

APP_NAME       := DeskPet
BUNDLE         := $(APP_NAME).app
CONFIG         ?= debug
BUILD_DIR      := .build
# Deferred so `make dist` (CONFIG=release) copies the release binary, not debug.
BIN_DIR         = $(BUILD_DIR)/$(CONFIG)
BIN             = $(BIN_DIR)/$(APP_NAME)
# SPM names resource bundles <PackageName>_<TargetName>.bundle
RESOURCE_BUNDLE := $(APP_NAME)_DeskPetKit.bundle
INFO_PLIST     := Support/Info.plist
ENTITLEMENTS   := Support/DeskPet.entitlements
ICON           := Support/AppIcon.icns
ICON_SRC       := docs/app-icon.png
DIST_DIR       := dist
DMG            := $(APP_NAME).dmg

.PHONY: all build test run run-debug app clean dist dmg notarize icon e2e

all: app

build:
	swift build --configuration $(CONFIG)

test:
	swift test

e2e: app
	bash Scripts/e2e_smoke.sh

icon: $(ICON)

$(ICON_SRC): Scripts/generate_app_icon.py
	python3 Scripts/generate_app_icon.py

$(ICON): $(ICON_SRC)
	rm -rf .build/AppIcon.iconset
	mkdir -p .build/AppIcon.iconset
	sips -z 16 16     $(ICON_SRC) --out .build/AppIcon.iconset/icon_16x16.png >/dev/null
	sips -z 32 32     $(ICON_SRC) --out .build/AppIcon.iconset/icon_16x16@2x.png >/dev/null
	sips -z 32 32     $(ICON_SRC) --out .build/AppIcon.iconset/icon_32x32.png >/dev/null
	sips -z 64 64     $(ICON_SRC) --out .build/AppIcon.iconset/icon_32x32@2x.png >/dev/null
	sips -z 128 128   $(ICON_SRC) --out .build/AppIcon.iconset/icon_128x128.png >/dev/null
	sips -z 256 256   $(ICON_SRC) --out .build/AppIcon.iconset/icon_128x128@2x.png >/dev/null
	sips -z 256 256   $(ICON_SRC) --out .build/AppIcon.iconset/icon_256x256.png >/dev/null
	sips -z 512 512   $(ICON_SRC) --out .build/AppIcon.iconset/icon_256x256@2x.png >/dev/null
	sips -z 512 512   $(ICON_SRC) --out .build/AppIcon.iconset/icon_512x512.png >/dev/null
	sips -z 1024 1024 $(ICON_SRC) --out .build/AppIcon.iconset/icon_512x512@2x.png >/dev/null
	iconutil -c icns .build/AppIcon.iconset -o $(ICON)
	rm -rf .build/AppIcon.iconset

# Assemble the .app bundle. Bundle.module resolves the resource bundle from
# Bundle.main.resourceURL, which is Contents/Resources.
app: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp $(INFO_PLIST) $(BUNDLE)/Contents/Info.plist
	cp -R $(BIN_DIR)/$(RESOURCE_BUNDLE) $(BUNDLE)/Contents/Resources/
	if [ -f $(ICON) ]; then cp $(ICON) $(BUNDLE)/Contents/Resources/AppIcon.icns; fi
	printf 'APPL????' > $(BUNDLE)/Contents/PkgInfo
	@# Ad-hoc hardened-runtime signature. A Developer ID identity (and
	@# notarization) replaces `-` once an Apple Developer account is available.
	codesign --force --sign - --options runtime --entitlements $(ENTITLEMENTS) $(BUNDLE)
	@echo "built $(BUNDLE)"

run: CONFIG=release
run: app
	open $(BUNDLE)

# Debug build with developer menu items / DESKPET_DEBUG_* harness.
run-debug:
	$(MAKE) CONFIG=debug app
	open $(BUNDLE)

dist: CONFIG=release
dist: dmg

dmg: app
	rm -rf $(DIST_DIR)
	mkdir -p $(DIST_DIR)
	cp -R $(BUNDLE) $(DIST_DIR)/
	rm -f $(DMG)
	hdiutil create -volname $(APP_NAME) -srcfolder $(DIST_DIR) -ov -format UDZO $(DMG)
	@echo "built $(DMG)"

notarize:
	@if ! xcrun notarytool --help >/dev/null 2>&1; then \
		echo "error: notarytool is unavailable."; \
		echo "Notarization needs full Xcode and an Apple Developer account."; \
		echo "This environment has Command Line Tools only; ship the ad-hoc DMG from 'make dmg'."; \
		exit 1; \
	fi
	@echo "error: notarytool is present but APPLE_ID / API key credentials are not configured."
	@exit 1

clean:
	rm -rf $(BUILD_DIR) $(BUNDLE) $(DIST_DIR) $(DMG)
