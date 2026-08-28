import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import DeskPetKit

@Suite("GIF decoding")
struct GIFDecoderTests {

    // MARK: Delay clamping (pure)

    @Test("unclamped delay wins when present")
    func prefersUnclampedDelay() {
        #expect(GIFDecoder.normalizedDelay(unclamped: 0.05, clamped: 0.1) == 0.05)
    }

    @Test("falls back to the clamped delay")
    func fallsBackToClampedDelay() {
        #expect(GIFDecoder.normalizedDelay(unclamped: nil, clamped: 0.07) == 0.07)
    }

    @Test("implausibly short delays become 100ms", arguments: [0.0, 0.001, 0.01])
    func clampsShortDelays(value: Double) {
        #expect(GIFDecoder.normalizedDelay(unclamped: value, clamped: nil) == GIFDecoder.defaultDelay)
    }

    @Test("the clamping threshold itself is not clamped")
    func thresholdIsInclusive() {
        #expect(GIFDecoder.normalizedDelay(unclamped: 0.011, clamped: nil) == 0.011)
    }

    @Test("absent delays become 100ms")
    func missingDelaysDefault() {
        #expect(GIFDecoder.normalizedDelay(unclamped: nil, clamped: nil) == GIFDecoder.defaultDelay)
    }

    // MARK: End-to-end with a synthetic GIF

    /// Writes a GIF with explicit per-frame delays to a temporary file.
    private func makeGIF(delays: [Double], size: Int = 4) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-test-\(UUID().uuidString).gif")
        let destination = try #require(
            CGImageDestinationCreateWithURL(
                url as CFURL, UTType.gif.identifier as CFString, delays.count, nil
            )
        )

        for delay in delays {
            let context = try #require(CGContext(
                data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(gray: CGFloat(delay), alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            let image = try #require(context.makeImage())
            let properties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay] as CFDictionary
            ]
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }

        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test("a synthetic GIF decodes with the expected frame count and size")
    func decodesSyntheticGIF() throws {
        let url = try makeGIF(delays: [0.08, 0.08, 0.08], size: 6)
        defer { try? FileManager.default.removeItem(at: url) }

        let decoded = try GIFDecoder.decode(url: url)
        #expect(decoded.frames.count == 3)
        #expect(decoded.frameDurations.count == 3)
        #expect(decoded.pixelSize == CGSize(width: 6, height: 6))
        #expect(abs(decoded.totalDuration - 0.24) < 0.001)
    }

    @Test("a GIF authored with 0ms delays plays at 100ms per frame")
    func clampsZeroDelayGIF() throws {
        let url = try makeGIF(delays: [0, 0])
        defer { try? FileManager.default.removeItem(at: url) }

        let metadata = try GIFDecoder.probe(url: url)
        #expect(metadata.frameCount == 2)
        #expect(metadata.frameDurations == [GIFDecoder.defaultDelay, GIFDecoder.defaultDelay])
        #expect(abs(metadata.totalDuration - 0.2) < 0.001)
    }

    @Test("probe and decode agree")
    func probeMatchesDecode() throws {
        let url = try makeGIF(delays: [0.05, 0.12])
        defer { try? FileManager.default.removeItem(at: url) }

        let probed = try GIFDecoder.probe(url: url)
        let decoded = try GIFDecoder.decode(url: url)
        #expect(probed == decoded.metadata)
    }

    // MARK: Failure modes

    @Test("a missing file throws unreadableSource")
    func missingFileThrows() {
        let url = URL(fileURLWithPath: "/nonexistent/deskpet/none.gif")
        #expect(throws: GIFDecoderError.unreadableSource(url)) {
            _ = try GIFDecoder.probe(url: url)
        }
    }

    @Test("a non-GIF file does not decode as a GIF")
    func nonGIFThrows() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-test-\(UUID().uuidString).txt")
        try Data("not an image".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: (any Error).self) {
            _ = try GIFDecoder.probe(url: url)
        }
    }

    // MARK: Every bundled asset

    @Test("every bundled GIF probes to at least one frame with a positive duration")
    func allBundledAssetsProbe() throws {
        let root = try #require(PetAssetLoader.bundledRoot)
        let enumerator = try #require(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        )

        var probed = 0
        var totalFrames = 0
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "gif" {
            let metadata = try GIFDecoder.probe(url: url)
            #expect(metadata.frameCount > 0, "no frames: \(url.lastPathComponent)")
            #expect(metadata.totalDuration > 0, "zero duration: \(url.lastPathComponent)")
            #expect(metadata.pixelSize.width > 0 && metadata.pixelSize.height > 0,
                    "zero size: \(url.lastPathComponent)")
            #expect(metadata.frameDurations.allSatisfy { $0 >= GIFDecoder.minimumDelay },
                    "unclamped short delay: \(url.lastPathComponent)")
            probed += 1
            totalFrames += metadata.frameCount
        }

        #expect(probed == 84, "expected 84 bundled GIFs, probed \(probed)")
        print("probed \(probed) bundled GIFs, \(totalFrames) frames total")
    }

    @Test("the default Line Dog idle animation decodes to real frames")
    func lineDogIdleDecodes() throws {
        let definition = PetAppearances.assetDefinition(appearance: .lineDog, state: .idle)
        let urls = PetAssetLoader.urls(for: definition)
        #expect(urls.count == 4)

        for url in urls {
            let decoded = try GIFDecoder.decode(url: url)
            #expect(decoded.frames.count > 1, "\(url.lastPathComponent) is not animated")
            #expect(decoded.pixelSize.width > 0)
        }
    }
}
