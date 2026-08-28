import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import DeskPetKit

@Suite("Custom assets")
struct CustomAssetTests {
    private func makeGIF(named: String = "sample.gif") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "deskpet-import-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(named)
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 1, nil)
        )
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try #require(context.makeImage())
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test("non-GIF sources are rejected")
    func rejectsNonGIF() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-support-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: support) }

        #expect(
            CustomAssetImporter.importGIF(
                state: .idle, from: source, into: support, now: Date()
            ) == nil
        )
    }

    @Test("a GIF is copied under custom_pet_assets/<state>/ with a sanitized name")
    func copiesIntoStateFolder() throws {
        let source = try makeGIF(named: "My Pet.gif")
        defer { try? FileManager.default.removeItem(at: source) }

        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-support-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: support) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let asset = try #require(
            CustomAssetImporter.importGIF(state: .idle, from: source, into: support, now: now)
        )

        #expect(asset.originalName == "My Pet.gif")
        #expect(asset.relativePath.hasPrefix("custom_pet_assets/idle/idle-"))
        #expect(asset.relativePath.hasSuffix("-My-Pet.gif"))
        #expect(Settings.isValidCustomAssetPath(asset.relativePath))

        let dest = support.appendingPathComponent(asset.relativePath)
        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(PetAssetLoader.isInsideCustomRoot(dest, supportDirectory: support))
    }

    @Test("path traversal inside a custom_pet_assets prefix is rejected")
    func rejectsTraversalInsidePrefix() {
        #expect(!Settings.isValidCustomAssetPath("custom_pet_assets/idle/../../etc/passwd.gif"))
        #expect(!Settings.isValidCustomAssetPath("custom_pet_assets/../secret.gif"))
        #expect(!Settings.isValidCustomAssetPath("custom_pet_assets/idle/./a.gif"))
        #expect(Settings.isValidCustomAssetPath("custom_pet_assets/idle/a.gif"))
    }

    @Test("PetAssetLoader refuses a resolved path outside the custom root")
    func loaderRefusesEscapingURL() {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-support-\(UUID().uuidString)")
        let previous = PetAssetLoader.supportDirectory
        PetAssetLoader.supportDirectory = support
        defer { PetAssetLoader.supportDirectory = previous }

        let definition = PetAssetDefinition(
            paths: ["custom_pet_assets/idle/../../etc/passwd.gif"],
            source: .custom
        )
        #expect(PetAssetLoader.url(for: definition) == nil)
    }

    @Test("sanitizing replaces characters outside the allow-list")
    func sanitizesFileName() {
        #expect(CustomAssetImporter.sanitizeFileName("My Pet.gif") == "My-Pet.gif")
        #expect(CustomAssetImporter.sanitizeFileName("ok_file-1.gif") == "ok_file-1.gif")
    }
}

@Suite("Custom appearance selection")
struct CustomAppearanceSelectionTests {
    @Test("idle is required before a custom appearance is usable")
    func idleRequired() {
        let happyOnly = CustomPetAppearance(
            name: "Custom",
            assets: [
                .happy: CustomPetAsset(
                    relativePath: "custom_pet_assets/happy/h.gif",
                    originalName: "h.gif",
                    updatedAt: 1
                )
            ]
        )
        #expect(!PetAppearances.hasRequiredAssets(happyOnly))

        var settings = Settings.defaults
        settings.petAppearanceID = .custom
        settings.customPetAppearance = happyOnly
        #expect(settings.normalized().petAppearanceID == Settings.defaults.petAppearanceID)
    }

    @Test("idle plus optional states is selectable")
    func idleMakesReady() {
        let custom = CustomPetAppearance(
            name: "Custom",
            assets: [
                .idle: CustomPetAsset(
                    relativePath: "custom_pet_assets/idle/i.gif",
                    originalName: "i.gif",
                    updatedAt: 1
                )
            ]
        )
        #expect(PetAppearances.hasRequiredAssets(custom))
        var settings = Settings.defaults
        settings.petAppearanceID = .custom
        settings.customPetAppearance = custom
        #expect(settings.normalized().petAppearanceID == .custom)
    }
}

@Suite("Custom asset wiring", .serialized)
@MainActor
struct CustomAssetWiringTests {
    private func makeGIF() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "deskpet-import-\(UUID().uuidString).gif"
        )
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 1, nil)
        )
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(gray: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try #require(context.makeImage())
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private func makeState() -> (AppState, () -> Void) {
        let suiteName = "com.dhanushprince.deskpet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-tests-\(UUID().uuidString)")
        let persistence = Persistence(defaults: defaults, supportDirectory: directory)
        let state = AppState(persistence: persistence, clock: TestClock(), random: { 0.5 })
        return (state, {
            state.stop()
            state.petWindow.hide()
            persistence.reset()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    @Test("importing idle selects the custom appearance")
    func importIdleSelectsCustom() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let source = try makeGIF()
        defer { try? FileManager.default.removeItem(at: source) }
        let (state, cleanup) = makeState()
        defer { cleanup() }

        let asset = try #require(state.importCustomAsset(from: source, for: .idle))
        #expect(state.settings.petAppearanceID == .custom)
        #expect(state.settings.customPetAppearance?.assets[.idle]?.relativePath == asset.relativePath)
        #expect(state.petWindow.appearance == .custom)
    }

    @Test("removing idle deselects custom")
    func removeIdleDeselects() throws {
        try #require(!NSScreen.screens.isEmpty, "no displays attached")
        let source = try makeGIF()
        defer { try? FileManager.default.removeItem(at: source) }
        let (state, cleanup) = makeState()
        defer { cleanup() }

        _ = state.importCustomAsset(from: source, for: .idle)
        state.removeCustomAsset(for: .idle)
        #expect(state.settings.petAppearanceID != .custom)
        #expect(state.settings.customPetAppearance == nil)
    }
}
