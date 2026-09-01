import Foundation

/// User preferences. Field names match the persisted JSON keys used by the
/// Electron build so migrated data decodes without a translation layer.
public struct Settings: Equatable, Codable, Sendable {
    public var petAppearanceID: PetAppearanceID
    public var customPetAppearance: CustomPetAppearance?
    public var onboardingDismissed: Bool
    public var launchAtLoginEnabled: Bool
    public var checkUpdatesOnLaunchEnabled: Bool
    public var breakReminderEnabled: Bool
    public var breakIntervalMinutes: Int
    public var breakRunDurationSeconds: Int
    public var hydrationReminderEnabled: Bool
    public var hydrationIntervalMinutes: Int
    public var focusDurationMinutes: Int
    public var distractionDetectionEnabled: Bool
    public var distractionGraceSeconds: Int
    public var distractionBlockedApps: [String]
    public var distractionBlockedKeywords: [String]
    public var hidePetDuringMeetings: Bool

    /// `language` is intentionally absent: the Electron build was English-only
    /// by the final commit, and the i18n indirection was dropped in the rewrite.

    enum CodingKeys: String, CodingKey {
        case petAppearanceID = "petAppearanceId"
        case customPetAppearance
        case onboardingDismissed
        case launchAtLoginEnabled
        case checkUpdatesOnLaunchEnabled
        case breakReminderEnabled
        case breakIntervalMinutes
        case breakRunDurationSeconds
        case hydrationReminderEnabled
        case hydrationIntervalMinutes
        case focusDurationMinutes
        case distractionDetectionEnabled
        case distractionGraceSeconds
        case distractionBlockedApps
        case distractionBlockedKeywords
        case hidePetDuringMeetings
    }

    /// Ported from `DEFAULT_SETTINGS`.
    public static let defaults = Settings(
        petAppearanceID: .lineDog,
        customPetAppearance: nil,
        onboardingDismissed: false,
        launchAtLoginEnabled: false,
        checkUpdatesOnLaunchEnabled: false,
        breakReminderEnabled: true,
        breakIntervalMinutes: 45,
        breakRunDurationSeconds: 60,
        hydrationReminderEnabled: true,
        hydrationIntervalMinutes: 90,
        focusDurationMinutes: 25,
        distractionDetectionEnabled: false,
        distractionGraceSeconds: 8,
        distractionBlockedApps: ["Steam", "Discord", "Telegram"],
        distractionBlockedKeywords: [
            "youtube", "youtu.be", "twitter", "x.com", "instagram",
            "reddit", "tiktok", "netflix", "twitch", "facebook"
        ],
        hidePetDuringMeetings: true
    )

    /// Missing keys fall back to defaults, so a partial or older payload decodes
    /// cleanly. Mirrors the `{...DEFAULT_SETTINGS, ...stored}` spread.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings.defaults

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            // A decode failure or an absent key both fall back, mirroring the
            // `{...DEFAULT_SETTINGS, ...stored}` spread.
            ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }

        // Unknown appearance identifiers collapse to the default.
        let rawAppearance = try? container.decodeIfPresent(String.self, forKey: .petAppearanceID)
        petAppearanceID = PetAppearanceID(persisted: rawAppearance ?? nil)
        customPetAppearance = try? container.decodeIfPresent(
            CustomPetAppearance.self, forKey: .customPetAppearance
        )

        onboardingDismissed = value(.onboardingDismissed, defaults.onboardingDismissed)
        launchAtLoginEnabled = value(.launchAtLoginEnabled, defaults.launchAtLoginEnabled)
        checkUpdatesOnLaunchEnabled = value(
            .checkUpdatesOnLaunchEnabled, defaults.checkUpdatesOnLaunchEnabled
        )
        breakReminderEnabled = value(.breakReminderEnabled, defaults.breakReminderEnabled)
        breakIntervalMinutes = value(.breakIntervalMinutes, defaults.breakIntervalMinutes)
        breakRunDurationSeconds = value(
            .breakRunDurationSeconds, defaults.breakRunDurationSeconds
        )
        hydrationReminderEnabled = value(
            .hydrationReminderEnabled, defaults.hydrationReminderEnabled
        )
        hydrationIntervalMinutes = value(
            .hydrationIntervalMinutes, defaults.hydrationIntervalMinutes
        )
        focusDurationMinutes = value(.focusDurationMinutes, defaults.focusDurationMinutes)
        distractionDetectionEnabled = value(
            .distractionDetectionEnabled, defaults.distractionDetectionEnabled
        )
        distractionGraceSeconds = value(
            .distractionGraceSeconds, defaults.distractionGraceSeconds
        )
        distractionBlockedApps = value(.distractionBlockedApps, defaults.distractionBlockedApps)
        distractionBlockedKeywords = value(
            .distractionBlockedKeywords, defaults.distractionBlockedKeywords
        )
        hidePetDuringMeetings = value(.hidePetDuringMeetings, defaults.hidePetDuringMeetings)
    }

    public init(
        petAppearanceID: PetAppearanceID,
        customPetAppearance: CustomPetAppearance?,
        onboardingDismissed: Bool,
        launchAtLoginEnabled: Bool,
        checkUpdatesOnLaunchEnabled: Bool,
        breakReminderEnabled: Bool,
        breakIntervalMinutes: Int,
        breakRunDurationSeconds: Int,
        hydrationReminderEnabled: Bool,
        hydrationIntervalMinutes: Int,
        focusDurationMinutes: Int,
        distractionDetectionEnabled: Bool,
        distractionGraceSeconds: Int,
        distractionBlockedApps: [String],
        distractionBlockedKeywords: [String],
        hidePetDuringMeetings: Bool = true
    ) {
        self.petAppearanceID = petAppearanceID
        self.customPetAppearance = customPetAppearance
        self.onboardingDismissed = onboardingDismissed
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.checkUpdatesOnLaunchEnabled = checkUpdatesOnLaunchEnabled
        self.breakReminderEnabled = breakReminderEnabled
        self.breakIntervalMinutes = breakIntervalMinutes
        self.breakRunDurationSeconds = breakRunDurationSeconds
        self.hydrationReminderEnabled = hydrationReminderEnabled
        self.hydrationIntervalMinutes = hydrationIntervalMinutes
        self.focusDurationMinutes = focusDurationMinutes
        self.distractionDetectionEnabled = distractionDetectionEnabled
        self.distractionGraceSeconds = distractionGraceSeconds
        self.distractionBlockedApps = distractionBlockedApps
        self.distractionBlockedKeywords = distractionBlockedKeywords
        self.hidePetDuringMeetings = hidePetDuringMeetings
    }
}

// MARK: - Limits

/// Ranges the settings UI enforces.
///
/// These live here rather than in the view because `normalizeSettings` only ever
/// clamped `breakRunDurationSeconds`; the Electron build relied on its number
/// inputs' `min`/`max` for the rest, and those bounds are reproduced exactly.
public enum SettingsLimits {
    public static let breakIntervalMinutes = 1...900
    public static let breakRunDurationSeconds = 10...900
    public static let hydrationIntervalMinutes = 1...900
    public static let focusDurationMinutes = 1...900
    public static let distractionGraceSeconds = 0...900

    /// Clamps a value into a range, for use when a field loses focus.
    public static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - Normalization

public extension Settings {
    /// Minimum break-run length, from `normalizeSettings`.
    static let minimumBreakRunDurationSeconds = 10

    /// Ported from `normalizeSettings`.
    ///
    /// Only `breakRunDurationSeconds` and the appearance selection are corrected
    /// here, exactly as in the Electron build — the other intervals were
    /// constrained by the settings UI rather than the store. The scheduler
    /// additionally refuses non-positive intervals so a corrupt value cannot
    /// produce a runaway timer.
    func normalized() -> Settings {
        var result = self

        // A custom appearance without the required states is not selectable.
        let custom = Self.normalizeCustom(customPetAppearance)
        result.customPetAppearance = custom
        if petAppearanceID == .custom, !PetAppearances.hasRequiredAssets(custom) {
            result.petAppearanceID = Settings.defaults.petAppearanceID
        }

        result.breakRunDurationSeconds = Self.normalizeNumber(
            breakRunDurationSeconds,
            fallback: Settings.defaults.breakRunDurationSeconds,
            minimum: Self.minimumBreakRunDurationSeconds
        )
        return result
    }

    /// `normalizeNumber`: round, then apply a floor.
    static func normalizeNumber(_ value: Int, fallback: Int, minimum: Int) -> Int {
        max(minimum, value)
    }

    /// Ported from `normalizeCustomPetAppearance`: drop assets whose paths are
    /// not GIFs under `custom_pet_assets/`, and drop the appearance entirely if
    /// nothing survives.
    static func normalizeCustom(_ custom: CustomPetAppearance?) -> CustomPetAppearance? {
        guard let custom else { return nil }

        var assets: [PetState: CustomPetAsset] = [:]
        for (state, asset) in custom.assets where isValidCustomAssetPath(asset.relativePath) {
            assets[state] = asset
        }
        guard !assets.isEmpty else { return nil }

        let trimmed = custom.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return CustomPetAppearance(
            name: trimmed.isEmpty ? "Custom Pet" : trimmed,
            assets: assets
        )
    }

    static func isValidCustomAssetPath(_ path: String) -> Bool {
        guard path.hasPrefix("custom_pet_assets/"),
              path.lowercased().hasSuffix(".gif")
        else { return false }
        // Reject `.` / `..` segments so a prefix match cannot walk out of the
        // custom root after the path is resolved (the `pawpal-asset` handler).
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        return !segments.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty })
    }
}
