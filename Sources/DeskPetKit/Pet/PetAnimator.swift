import AppKit
import CoreGraphics
import Foundation
import QuartzCore

/// Plays a decoded GIF on a `CALayer` using a single discrete keyframe
/// animation.
///
/// Chosen over `NSImageView.animates` because that redraws through the view
/// system every frame; one `CAKeyframeAnimation` hands the whole sequence to the
/// render server and costs no per-frame main-thread work.
public final class PetAnimator {
    /// Cache key: a resolved file URL. Frames are shared between plays because
    /// the pet cycles back through the same handful of animations constantly.
    private static var cache: [URL: DecodedGIF] = [:]
    private static let cacheLimit = 24

    private let layer: CALayer
    /// Re-triggers the animation for assets that declare `replayIntervalMs`.
    private var replayTimer: Timer?
    private var currentURL: URL?

    private static let animationKey = "deskpet.frames"

    public init(layer: CALayer) {
        self.layer = layer
        layer.contentsGravity = .resizeAspect
        // Pixel-art GIFs: nearest is cheaper and sharper than trilinear.
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        layer.drawsAsynchronously = true
    }

    deinit {
        replayTimer?.invalidate()
    }

    /// Normalized keyframe times for a discrete animation.
    ///
    /// Core Animation requires `keyTimes` to hold one more entry than `values`
    /// when `calculationMode` is `.discrete`: entry *i* is the fraction of the
    /// total duration at which frame *i* appears, and the trailing 1.0 closes
    /// the final frame's interval.
    public static func keyTimes(durations: [TimeInterval]) -> [NSNumber] {
        let total = durations.reduce(0, +)
        guard total > 0, !durations.isEmpty else { return [0, 1] }

        var times: [NSNumber] = []
        times.reserveCapacity(durations.count + 1)
        var elapsed: TimeInterval = 0
        for duration in durations {
            times.append(NSNumber(value: elapsed / total))
            elapsed += duration
        }
        times.append(NSNumber(value: 1.0))
        return times
    }

    /// Plays one variant of a definition. Returns false when the asset could
    /// not be loaded, so the caller can fall back.
    @discardableResult
    public func play(definition: PetAssetDefinition, variant: Int = 0) -> Bool {
        guard !definition.paths.isEmpty else { return false }
        // Matches `getPetAsset`: variant indices wrap rather than clamp.
        let index = abs(variant) % definition.paths.count
        guard let url = PetAssetLoader.url(for: definition, variant: index) else { return false }

        guard let gif = Self.decoded(url) else { return false }

        currentURL = url
        apply(gif)
        scheduleReplay(intervalMs: definition.replayIntervalMs)
        return true
    }

    public func stop() {
        replayTimer?.invalidate()
        replayTimer = nil
        layer.removeAnimation(forKey: Self.animationKey)
        currentURL = nil
    }

    /// Intrinsic pixel size of the animation currently playing.
    public var currentPixelSize: CGSize? {
        currentURL.flatMap { Self.cache[$0]?.pixelSize }
    }

    // MARK: - Internals

    private func apply(_ gif: DecodedGIF) {
        guard let first = gif.frames.first else { return }

        // Static single-frame GIF: no animation needed.
        layer.contents = first
        guard gif.frames.count > 1 else {
            layer.removeAnimation(forKey: Self.animationKey)
            return
        }

        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = gif.frames
        animation.keyTimes = Self.keyTimes(durations: gif.frameDurations)
        animation.duration = gif.totalDuration
        animation.calculationMode = .discrete
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        // Frames must appear exactly as authored, with no interpolation or
        // easing between them.
        animation.fillMode = .forwards

        layer.removeAnimation(forKey: Self.animationKey)
        layer.add(animation, forKey: Self.animationKey)
    }

    /// The Electron renderer restarted these animations by mutating the `<img>`
    /// src on an interval; re-adding the animation is the equivalent here.
    private func scheduleReplay(intervalMs: Int?) {
        replayTimer?.invalidate()
        replayTimer = nil
        guard let intervalMs, intervalMs > 0 else { return }

        let timer = Timer(
            timeInterval: TimeInterval(intervalMs) / 1000,
            repeats: true
        ) { [weak self] _ in
            guard let self, let url = self.currentURL, let gif = Self.cache[url] else { return }
            self.apply(gif)
        }
        RunLoop.main.add(timer, forMode: .common)
        replayTimer = timer
    }

    private static func decoded(_ url: URL) -> DecodedGIF? {
        if let cached = cache[url] { return cached }
        do {
            let gif = try GIFDecoder.decode(url: url)
            if cache.count >= cacheLimit {
                // Crude eviction: the working set is small and uniform, so
                // dropping an arbitrary entry is enough to bound memory.
                cache.removeValue(forKey: cache.keys.first!)
            }
            cache[url] = gif
            return gif
        } catch {
            NSLog("DeskPet: failed to decode \(url.lastPathComponent): \(error)")
            return nil
        }
    }
}
