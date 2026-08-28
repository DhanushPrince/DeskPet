import CoreGraphics
import Foundation

/// The pet occupies a centred fraction of its window; the surrounding margin is
/// transparent and must not intercept clicks.
///
/// Ported from `src/renderer/src/petHitbox.ts`.
public enum PetHitbox {
    /// Whether `point` falls inside the centred hitbox of `rect`.
    ///
    /// `point` and `rect` must be expressed in the same coordinate space. The
    /// test is symmetric about the centre, so it holds for both top-left and
    /// bottom-left origins.
    ///
    /// - Parameter scale: fraction of each dimension that counts as the pet.
    ///   Values outside `(0, 1]` are rejected rather than clamped, matching the
    ///   original guard.
    public static func contains(
        _ point: CGPoint,
        in rect: CGRect,
        scale: Double = Constants.hitboxScale
    ) -> Bool {
        guard rect.width > 0, rect.height > 0, scale > 0, scale <= 1 else { return false }

        let insetX = rect.width * (1 - scale) / 2
        let insetY = rect.height * (1 - scale) / 2
        let left = rect.minX + insetX
        let right = rect.minX + rect.width - insetX
        let top = rect.minY + insetY
        let bottom = rect.minY + rect.height - insetY

        return point.x >= left && point.x <= right && point.y >= top && point.y <= bottom
    }

    /// The hitbox rectangle itself, for diagnostics and tests.
    public static func rect(in rect: CGRect, scale: Double = Constants.hitboxScale) -> CGRect {
        guard rect.width > 0, rect.height > 0, scale > 0, scale <= 1 else { return .null }
        return rect.insetBy(
            dx: rect.width * (1 - scale) / 2,
            dy: rect.height * (1 - scale) / 2
        )
    }
}
