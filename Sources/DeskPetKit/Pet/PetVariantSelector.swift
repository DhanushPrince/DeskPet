import Foundation

/// Variant choice for states that have several animations.
///
/// Ported from `randomVariant` in `PetView.tsx`. Selection is deliberately
/// non-cryptographic; it only decides which GIF plays.
public enum PetVariantSelector {
    /// - Parameters:
    ///   - count: number of available variants.
    ///   - previous: variant currently showing, avoided when possible so a
    ///     rotation visibly changes the animation.
    ///   - random: returns a value in `0..<count`; injected for testing.
    public static func variant(
        count: Int,
        previous: Int? = nil,
        random: (Int) -> Int = { Int.random(in: 0..<$0) }
    ) -> Int {
        guard count > 1 else { return 0 }
        var next = random(count)
        // Guard against a bad generator as well as an out-of-range injection.
        next = abs(next) % count
        if let previous, next == previous {
            next = (next + 1) % count
        }
        return next
    }

    /// Whether a state should keep cycling variants while it stays active.
    public static func rotates(_ state: PetState, variantCount: Int) -> Bool {
        Constants.continuousAssetStates.contains(state) && variantCount > 1
    }
}
