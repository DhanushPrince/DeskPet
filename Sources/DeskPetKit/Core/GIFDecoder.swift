import CoreGraphics
import Foundation
import ImageIO

/// Frame timing and geometry for a GIF, without decoding pixel data.
public struct GIFMetadata: Equatable, Sendable {
    public let frameCount: Int
    /// Per-frame display duration in seconds, already clamped.
    public let frameDurations: [TimeInterval]
    public let totalDuration: TimeInterval
    public let pixelSize: CGSize
}

/// A fully decoded GIF. Frames are retained, so prefer `probe` when only
/// timing is needed.
public struct DecodedGIF {
    public let frames: [CGImage]
    public let frameDurations: [TimeInterval]
    public let totalDuration: TimeInterval
    public let pixelSize: CGSize

    public var metadata: GIFMetadata {
        GIFMetadata(
            frameCount: frames.count,
            frameDurations: frameDurations,
            totalDuration: totalDuration,
            pixelSize: pixelSize
        )
    }
}

public enum GIFDecoderError: Error, Equatable {
    case unreadableSource(URL)
    case noFrames(URL)
    case undecodableFrame(URL, index: Int)
}

public enum GIFDecoder {
    /// Delays at or below this are treated as "unspecified" and replaced with
    /// `defaultDelay`. Matches the threshold browsers use, which is what the
    /// Electron build relied on for playback speed.
    public static let minimumDelay: TimeInterval = 0.011
    public static let defaultDelay: TimeInterval = 0.1

    /// Frame delay selection and clamping, split out as a pure function so the
    /// rule is testable without constructing a GIF.
    ///
    /// Prefers the unclamped value (the GIF's true authored delay) and falls
    /// back to the clamped one, then substitutes `defaultDelay` for anything
    /// implausibly short. Without this, GIFs authored with a 0ms delay animate
    /// far faster natively than they did in the Electron renderer.
    public static func normalizedDelay(unclamped: Double?, clamped: Double?) -> TimeInterval {
        let raw = unclamped ?? clamped ?? 0
        return raw < minimumDelay ? defaultDelay : raw
    }

    /// Reads frame timing and size without decoding pixels.
    public static func probe(url: URL) throws -> GIFMetadata {
        let source = try imageSource(url)
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw GIFDecoderError.noFrames(url) }

        let durations = (0..<count).map { delay(in: source, at: $0) }
        return GIFMetadata(
            frameCount: count,
            frameDurations: durations,
            totalDuration: durations.reduce(0, +),
            pixelSize: pixelSize(in: source)
        )
    }

    /// Decodes every frame.
    public static func decode(url: URL) throws -> DecodedGIF {
        let source = try imageSource(url)
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw GIFDecoderError.noFrames(url) }

        var frames: [CGImage] = []
        var durations: [TimeInterval] = []
        frames.reserveCapacity(count)
        durations.reserveCapacity(count)

        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                throw GIFDecoderError.undecodableFrame(url, index: index)
            }
            frames.append(frame)
            durations.append(delay(in: source, at: index))
        }

        let size = frames.first.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
        return DecodedGIF(
            frames: frames,
            frameDurations: durations,
            totalDuration: durations.reduce(0, +),
            pixelSize: size
        )
    }

    // MARK: - Internals

    private static func imageSource(_ url: URL) throws -> CGImageSource {
        // kCGImageSourceShouldCache false: frames are pulled once into
        // CAKeyframeAnimation values, so ImageIO's cache is pure overhead.
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            throw GIFDecoderError.unreadableSource(url)
        }
        return source
    }

    private static func delay(in source: CGImageSource, at index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as NSDictionary?,
              let gif = properties[kCGImagePropertyGIFDictionary] as? NSDictionary
        else {
            return defaultDelay
        }
        return normalizedDelay(
            unclamped: gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double,
            clamped: gif[kCGImagePropertyGIFDelayTime] as? Double
        )
    }

    private static func pixelSize(in source: CGImageSource) -> CGSize {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double
        else {
            return .zero
        }
        return CGSize(width: width, height: height)
    }
}
