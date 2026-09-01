import Foundation
import Testing
@testable import DeskPetKit

/// Task 1 gate: the bundle template the Makefile copies into
/// `DeskPet.app/Contents/Info.plist` must be well formed and must mark the app
/// as an accessory (no Dock icon).
@Suite("Bundle smoke")
struct BundleSmokeTests {
    /// Repository root, derived from this file's location so the test does not
    /// depend on the working directory.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)     // .../Tests/DeskPetTests/BundleSmokeTests.swift
            .deletingLastPathComponent()     // .../Tests/DeskPetTests
            .deletingLastPathComponent()     // .../Tests
            .deletingLastPathComponent()     // repo root
    }

    private func loadInfoPlist() throws -> [String: Any] {
        let url = Self.repoRoot.appendingPathComponent("Support/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(plist as? [String: Any], "Info.plist is not a dictionary")
    }

    @Test("Info.plist parses as a non-empty dictionary")
    func infoPlistIsWellFormed() throws {
        let plist = try loadInfoPlist()
        #expect(!plist.isEmpty)
    }

    @Test("LSUIElement marks the app as accessory (no Dock icon)")
    func appIsAccessory() throws {
        let plist = try loadInfoPlist()
        #expect(plist["LSUIElement"] as? Bool == true)
    }

    @Test("Bundle identity matches the approved values")
    func bundleIdentity() throws {
        let plist = try loadInfoPlist()
        #expect(plist["CFBundleIdentifier"] as? String == "com.dhanushprince.deskpet")
        #expect(plist["CFBundleShortVersionString"] as? String == "1.0.3")
        #expect(plist["CFBundleExecutable"] as? String == "DeskPet")
        #expect(plist["CFBundlePackageType"] as? String == "APPL")
    }

    @Test("Minimum system version is macOS 14")
    func minimumSystemVersion() throws {
        let plist = try loadInfoPlist()
        #expect(plist["LSMinimumSystemVersion"] as? String == "14.0")
    }

    @Test("AppInfo falls back to literals outside an app bundle")
    func appInfoFallback() {
        // Under `swift test` there is no DeskPet.app, so the literals apply.
        #expect(AppInfo.name == "DeskPet")
        #expect(!AppInfo.version.isEmpty)
    }

    @Test("assembled app includes the DeskPetKit resource bundle")
    func kitResourceBundlePackaged() {
        let app = Self.repoRoot.appendingPathComponent("DeskPet.app")
        let inResources = app.appendingPathComponent("Contents/Resources/DeskPet_DeskPetKit.bundle")
        let petAssets = "PetAssets/LineDog/idle"
        #expect(
            FileManager.default.fileExists(atPath: inResources.appendingPathComponent(petAssets).path),
            "DeskPet_DeskPetKit.bundle must be under Contents/Resources"
        )
    }

    @Test("the app icon and entitlements files are present")
    func packagingFilesExist() {
        let icon = Self.repoRoot.appendingPathComponent("Support/AppIcon.icns")
        let entitlements = Self.repoRoot.appendingPathComponent("Support/DeskPet.entitlements")
        let artwork = Self.repoRoot.appendingPathComponent("docs/app-icon.png")
        #expect(FileManager.default.fileExists(atPath: icon.path))
        #expect(FileManager.default.fileExists(atPath: entitlements.path))
        #expect(FileManager.default.fileExists(atPath: artwork.path))
        #expect(FileManager.default.fileExists(
            atPath: Self.repoRoot.appendingPathComponent(".github/workflows/ci.yml").path
        ))
    }
}
