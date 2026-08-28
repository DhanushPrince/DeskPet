import Foundation

/// The 14 pet states, declared in the same order as `PET_STATE_ORDER` in the
/// Electron source so `allCases` is order-compatible with the original.
///
/// `CodingKeyRepresentable` matters: without it Swift encodes a
/// `[PetState: T]` dictionary as a flat array of alternating keys and values,
/// which would neither match nor decode the `{"idle": {...}}` shape written by
/// the Electron build.
public enum PetState: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    case idle
    case sitting
    case happy
    case breakPrompt
    case breakRunning
    case breakDone
    case hydrationPrompt
    case drinking
    case hydrationDone
    case focusGuard
    case focusAlert
    case focusDone
    case sad
    case sleeping
}

public enum PetFacing: String, Codable, Sendable {
    case left
    case right
}

/// Modes that suppress other reminders while active. `nil` in the Electron
/// source is represented here by an optional `BlockingMode?`.
public enum BlockingMode: String, Codable, Sendable {
    case breakPrompt = "break"
    case breakRun
    case hydration
    case focusWarning
}

/// The three bundled appearances. Raw values match the persisted identifiers
/// used by the Electron build so migrated settings keep working; note that
/// `lovartPuppy` is the Golden Puppy.
public enum BuiltInPetAppearanceID: String, CaseIterable, Codable, Sendable {
    case lovartPuppy
    case lineDog
    case xiaoJiMao
}

/// A selected appearance: one of the built-ins, or the user's custom pet.
public enum PetAppearanceID: String, CaseIterable, Codable, Sendable {
    case lovartPuppy
    case lineDog
    case xiaoJiMao
    case custom

    /// Mirrors `resolvePetAppearanceId`: unknown values collapse to `lineDog`.
    public init(persisted value: String?) {
        self = PetAppearanceID(rawValue: value ?? "") ?? .lineDog
    }

    /// Mirrors `resolveBuiltInPetAppearanceId`: `custom` and unknown values
    /// collapse to `lineDog`.
    public var builtIn: BuiltInPetAppearanceID {
        BuiltInPetAppearanceID(rawValue: rawValue) ?? .lineDog
    }
}
