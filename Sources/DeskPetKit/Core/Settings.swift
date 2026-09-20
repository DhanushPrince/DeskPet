import Foundation

/// How hydration reminders are timed.
public enum HydrationReminderStrategy: String, Equatable, Codable, Sendable, CaseIterable {
    /// Spread the day's remaining servings across the active window, rescheduling
    /// after each drink and stopping at the goal.
    case smartPacing
    /// A blind fixed interval (`hydrationIntervalMinutes`), the original
    /// behaviour.
    case fixedInterval
}

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
    public var hydrationServingMilliliters: Int
    public var hydrationTargetMilliliters: Int
    public var hydrationActiveStartMinutes: Int
    public var hydrationActiveEndMinutes: Int
    public var hydrationReminderStrategy: HydrationReminderStrategy
    public var hydrationStopAtGoal: Bool
    public var focusDurationMinutes: Int
    public var distractionDetectionEnabled: Bool
    public var distractionGraceSeconds: Int
    public var distractionBlockedApps: [String]
    public var distractionBlockedKeywords: [String]
    public var hidePetDuringMeetings: Bool
    public var showBreaksStat: Bool
    public var showWatersStat: Bool
    public var showFocusStat: Bool
    public var showDistractionsStat: Bool
    public var playOnDesktop: Bool

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
        case hydrationServingMilliliters
        case hydrationTargetMilliliters
        case hydrationActiveStartMinutes
        case hydrationActiveEndMinutes
        case hydrationReminderStrategy
        case hydrationStopAtGoal
        case focusDurationMinutes
        case distractionDetectionEnabled
        case distractionGraceSeconds
        case distractionBlockedApps
        case distractionBlockedKeywords
        case hidePetDuringMeetings
        case showBreaksStat
        case showWatersStat
        case showFocusStat
        case showDistractionsStat
        case playOnDesktop
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
        hydrationServingMilliliters: 250,
        hydrationTargetMilliliters: 2000,
        hydrationActiveStartMinutes: 8 * 60,
        hydrationActiveEndMinutes: 22 * 60,
        hydrationReminderStrategy: .smartPacing,
        hydrationStopAtGoal: true,
        focusDurationMinutes: 25,
        distractionDetectionEnabled: false,
        distractionGraceSeconds: 8,
        distractionBlockedApps: ["Steam", "Discord", "Telegram"],
        distractionBlockedKeywords: [
            "youtube", "youtu.be", "twitter", "x.com", "instagram",
            "reddit", "tiktok", "netflix", "twitch", "facebook"
        ],
        hidePetDuringMeetings: true,
        showBreaksStat: true,
        showWatersStat: true,
        showFocusStat: true,
        showDistractionsStat: true,
        playOnDesktop: false
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
        hydrationServingMilliliters = value(
            .hydrationServingMilliliters, defaults.hydrationServingMilliliters
        )
        hydrationTargetMilliliters = value(
            .hydrationTargetMilliliters, defaults.hydrationTargetMilliliters
        )
        hydrationActiveStartMinutes = value(
            .hydrationActiveStartMinutes, defaults.hydrationActiveStartMinutes
        )
        hydrationActiveEndMinutes = value(
            .hydrationActiveEndMinutes, defaults.hydrationActiveEndMinutes
        )
        // Unknown/legacy strategy strings collapse to the default.
        hydrationReminderStrategy = value(
            .hydrationReminderStrategy, defaults.hydrationReminderStrategy
        )
        hydrationStopAtGoal = value(.hydrationStopAtGoal, defaults.hydrationStopAtGoal)
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
        showBreaksStat = value(.showBreaksStat, defaults.showBreaksStat)
        showWatersStat = value(.showWatersStat, defaults.showWatersStat)
        showFocusStat = value(.showFocusStat, defaults.showFocusStat)
        showDistractionsStat = value(.showDistractionsStat, defaults.showDistractionsStat)
        // Absent playOnDesktop → true (preserves desktop roam for existing users).
        playOnDesktop = value(.playOnDesktop, true)
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
        hydrationServingMilliliters: Int = 250,
        hydrationTargetMilliliters: Int = 2000,
        hydrationActiveStartMinutes: Int = 8 * 60,
        hydrationActiveEndMinutes: Int = 22 * 60,
        hydrationReminderStrategy: HydrationReminderStrategy = .smartPacing,
        hydrationStopAtGoal: Bool = true,
        focusDurationMinutes: Int,
        distractionDetectionEnabled: Bool,
        distractionGraceSeconds: Int,
        distractionBlockedApps: [String],
        distractionBlockedKeywords: [String],
        hidePetDuringMeetings: Bool = true,
        showBreaksStat: Bool = true,
        showWatersStat: Bool = true,
        showFocusStat: Bool = true,
        showDistractionsStat: Bool = true,
        playOnDesktop: Bool = false
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
        self.hydrationServingMilliliters = hydrationServingMilliliters
        self.hydrationTargetMilliliters = hydrationTargetMilliliters
        self.hydrationActiveStartMinutes = hydrationActiveStartMinutes
        self.hydrationActiveEndMinutes = hydrationActiveEndMinutes
        self.hydrationReminderStrategy = hydrationReminderStrategy
        self.hydrationStopAtGoal = hydrationStopAtGoal
        self.focusDurationMinutes = focusDurationMinutes
        self.distractionDetectionEnabled = distractionDetectionEnabled
        self.distractionGraceSeconds = distractionGraceSeconds
        self.distractionBlockedApps = distractionBlockedApps
        self.distractionBlockedKeywords = distractionBlockedKeywords
        self.hidePetDuringMeetings = hidePetDuringMeetings
        self.showBreaksStat = showBreaksStat
        self.showWatersStat = showWatersStat
        self.showFocusStat = showFocusStat
        self.showDistractionsStat = showDistractionsStat
        self.playOnDesktop = playOnDesktop
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
    public static let hydrationServingMilliliters = 50...2000
    public static let hydrationTargetMilliliters = 0...8000
    public static let hydrationActiveStartMinutes = 0...1439
    public static let hydrationActiveEndMinutes = 0...1439
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
