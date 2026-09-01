import Foundation
import Testing
@testable import DeskPetKit

/// Ported from `tests/settingsStore.test.ts`.
@Suite("Settings normalization")
struct SettingsNormalizationTests {

    @Test("an empty payload decodes to the defaults")
    func emptyPayloadUsesDefaults() throws {
        let decoded = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        #expect(decoded.normalized() == Settings.defaults)
    }

    @Test("the defaults match DEFAULT_SETTINGS from the Electron source")
    func defaultsMatchSource() {
        let defaults = Settings.defaults
        #expect(defaults.petAppearanceID == .lineDog)
        #expect(defaults.breakReminderEnabled)
        #expect(defaults.breakIntervalMinutes == 45)
        #expect(defaults.breakRunDurationSeconds == 60)
        #expect(defaults.hydrationReminderEnabled)
        #expect(defaults.hydrationIntervalMinutes == 90)
        #expect(defaults.focusDurationMinutes == 25)
        #expect(!defaults.distractionDetectionEnabled)
        #expect(defaults.hidePetDuringMeetings)
        #expect(defaults.distractionGraceSeconds == 8)
        #expect(!defaults.launchAtLoginEnabled)
        #expect(!defaults.checkUpdatesOnLaunchEnabled)
        #expect(!defaults.onboardingDismissed)
        #expect(defaults.distractionBlockedApps == ["Steam", "Discord", "Telegram"])
        #expect(defaults.distractionBlockedKeywords == [
            "youtube", "youtu.be", "twitter", "x.com", "instagram",
            "reddit", "tiktok", "netflix", "twitch", "facebook"
        ])
    }

    @Test("an unknown pet appearance falls back to the default")
    func unknownAppearanceFallsBack() throws {
        let json = #"{"petAppearanceId":"cat"}"#
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(decoded.petAppearanceID == Settings.defaults.petAppearanceID)
    }

    @Test("valid stored values are preserved")
    func preservesValidValues() throws {
        let json = """
        {"petAppearanceId":"lovartPuppy","launchAtLoginEnabled":true,
         "checkUpdatesOnLaunchEnabled":true,"breakRunDurationSeconds":90}
        """
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8)).normalized()
        #expect(decoded.petAppearanceID == .lovartPuppy)
        #expect(decoded.launchAtLoginEnabled)
        #expect(decoded.checkUpdatesOnLaunchEnabled)
        #expect(decoded.breakRunDurationSeconds == 90)
    }

    @Test("break run duration has a floor but no ceiling")
    func breakRunDurationFloor() {
        var settings = Settings.defaults

        settings.breakRunDurationSeconds = 5
        #expect(settings.normalized().breakRunDurationSeconds == 10)

        settings.breakRunDurationSeconds = 1200
        #expect(settings.normalized().breakRunDurationSeconds == 1200)

        settings.breakRunDurationSeconds = 10
        #expect(settings.normalized().breakRunDurationSeconds == 10)
    }

    @Test("a valid custom pet is preserved")
    func preservesValidCustomPet() throws {
        let json = """
        {"petAppearanceId":"custom","customPetAppearance":{"name":"My Pet","assets":{
          "idle":{"relativePath":"custom_pet_assets/idle/my-pet.gif",
                  "originalName":"my-pet.gif","updatedAt":1}}}}
        """
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8)).normalized()
        #expect(decoded.petAppearanceID == .custom)
        #expect(
            decoded.customPetAppearance?.assets[.idle]?.relativePath
                == "custom_pet_assets/idle/my-pet.gif"
        )
        #expect(decoded.customPetAppearance?.name == "My Pet")
    }

    @Test("a custom pet missing idle falls back to the default appearance")
    func customPetWithoutIdleFallsBack() throws {
        let json = """
        {"petAppearanceId":"custom","customPetAppearance":{"name":"My Pet","assets":{
          "happy":{"relativePath":"custom_pet_assets/happy/my-pet.gif",
                   "originalName":"my-pet.gif","updatedAt":1}}}}
        """
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8)).normalized()
        #expect(decoded.petAppearanceID == Settings.defaults.petAppearanceID)
    }

    @Test("custom assets outside custom_pet_assets or not GIFs are rejected")
    func rejectsInvalidCustomAssetPaths() {
        #expect(Settings.isValidCustomAssetPath("custom_pet_assets/idle/a.gif"))
        #expect(Settings.isValidCustomAssetPath("custom_pet_assets/idle/A.GIF"))
        #expect(!Settings.isValidCustomAssetPath("/etc/passwd"))
        #expect(!Settings.isValidCustomAssetPath("pet_assets/LineDog/idle/a.gif"))
        #expect(!Settings.isValidCustomAssetPath("custom_pet_assets/idle/a.png"))
        #expect(!Settings.isValidCustomAssetPath("../custom_pet_assets/idle/a.gif"))
        #expect(!Settings.isValidCustomAssetPath("custom_pet_assets/idle/../../etc/passwd.gif"))

        let bad = CustomPetAppearance(
            name: "Bad",
            assets: [.idle: CustomPetAsset(
                relativePath: "/etc/passwd", originalName: "x", updatedAt: 1
            )]
        )
        #expect(Settings.normalizeCustom(bad) == nil)
    }

    @Test("a blank custom pet name becomes the default label")
    func blankCustomNameGetsDefault() {
        let custom = CustomPetAppearance(
            name: "   ",
            assets: [.idle: CustomPetAsset(
                relativePath: "custom_pet_assets/idle/a.gif", originalName: "a.gif", updatedAt: 1
            )]
        )
        #expect(Settings.normalizeCustom(custom)?.name == "Custom Pet")
    }

    @Test("settings survive an encode/decode round trip")
    func roundTrip() throws {
        var settings = Settings.defaults
        settings.petAppearanceID = .xiaoJiMao
        settings.breakIntervalMinutes = 30
        settings.distractionBlockedApps = ["Slack"]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        #expect(decoded == settings)
    }
}

@Suite("Persistence", .serialized)
struct PersistenceTests {

    /// Isolated store per test: a private UserDefaults suite and a temp
    /// directory, so nothing touches the real user's data.
    private func makePersistence() -> (Persistence, () -> Void) {
        let suiteName = "com.dhanushprince.deskpet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-tests-\(UUID().uuidString)")
        let persistence = Persistence(defaults: defaults, supportDirectory: directory)

        return (persistence, {
            persistence.reset()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    @Test("an empty store reports the defaults")
    func emptyStoreReturnsDefaults() {
        let (persistence, cleanup) = makePersistence()
        defer { cleanup() }
        #expect(persistence.settings == Settings.defaults)
        #expect(persistence.petPosition == nil)
        #expect(!persistence.petHiddenByUser)
        #expect(!persistence.hasMigratedLegacyStore)
    }

    @Test("settings round-trip through UserDefaults")
    func settingsRoundTrip() {
        let (persistence, cleanup) = makePersistence()
        defer { cleanup() }

        var settings = Settings.defaults
        settings.breakIntervalMinutes = 20
        settings.petAppearanceID = .xiaoJiMao
        settings.distractionDetectionEnabled = true
        persistence.settings = settings

        let loaded = persistence.settings
        #expect(loaded.breakIntervalMinutes == 20)
        #expect(loaded.petAppearanceID == .xiaoJiMao)
        #expect(loaded.distractionDetectionEnabled)
    }

    @Test("settings are normalized on write")
    func settingsNormalizedOnWrite() {
        let (persistence, cleanup) = makePersistence()
        defer { cleanup() }

        var settings = Settings.defaults
        settings.breakRunDurationSeconds = 2
        persistence.settings = settings
        #expect(persistence.settings.breakRunDurationSeconds == 10)
    }

    @Test("pet position and hidden flag round-trip")
    func windowStateRoundTrip() {
        let (persistence, cleanup) = makePersistence()
        defer { cleanup() }

        persistence.petPosition = SavedWindowPosition(
            x: 100, y: 200, displayId: 7, relativeX: 0.25, relativeY: 0.75
        )
        persistence.petHiddenByUser = true

        let position = persistence.petPosition
        #expect(position?.x == 100)
        #expect(position?.displayId == 7)
        #expect(position?.relativeX == 0.25)
        #expect(persistence.petHiddenByUser)

        persistence.petPosition = nil
        #expect(persistence.petPosition == nil)
    }

    @Test("stats are written to and read from stats.json")
    func statsFileRoundTrip() {
        let (persistence, cleanup) = makePersistence()
        defer { cleanup() }

        let stats = DayStats(
            date: "2026-08-28", breaksTaken: 3, watersLogged: 5,
            focusMinutes: 50, focusWarnings: 1
        )
        persistence.currentStats = stats

        #expect(FileManager.default.fileExists(atPath: persistence.statsFileURL.path))
        #expect(persistence.currentStats == stats)
        // Writing the current day also records it in history.
        #expect(persistence.statsHistory["2026-08-28"] == stats)
    }

    @Test("a missing stats file reports a dateless empty day")
    func missingStatsFile() {
        let (persistence, cleanup) = makePersistence()
        defer { cleanup() }

        // Storage does not invent a date; StatsStore assigns one from its clock.
        let current = persistence.currentStats
        #expect(current.date.isEmpty)
        #expect(current.breaksTaken == 0)
        #expect(persistence.statsHistory.isEmpty)
    }
}

@Suite("Legacy migration", .serialized)
struct LegacyMigrationTests {

    private func makePersistence() -> (Persistence, URL, () -> Void) {
        let suiteName = "com.dhanushprince.deskpet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("deskpet-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let persistence = Persistence(defaults: defaults, supportDirectory: directory)

        return (persistence, directory, {
            persistence.reset()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        })
    }

    /// A realistic `deskpet.json`, including the `language` key the native build
    /// no longer models.
    static let realisticStore = """
    {
      "settings": {
        "language": "en",
        "petAppearanceId": "xiaoJiMao",
        "customPetAppearance": null,
        "onboardingDismissed": true,
        "launchAtLoginEnabled": true,
        "checkUpdatesOnLaunchEnabled": true,
        "breakReminderEnabled": true,
        "breakIntervalMinutes": 30,
        "breakRunDurationSeconds": 45,
        "hydrationReminderEnabled": false,
        "hydrationIntervalMinutes": 120,
        "focusDurationMinutes": 50,
        "distractionDetectionEnabled": true,
        "distractionGraceSeconds": 12,
        "distractionBlockedApps": ["Steam"],
        "distractionBlockedKeywords": ["youtube", "reddit"]
      },
      "stats": {
        "date": "2026-08-27",
        "breaksTaken": 4,
        "watersLogged": 6,
        "focusMinutes": 120,
        "focusWarnings": 2
      },
      "statsHistory": {
        "2026-08-26": {
          "date": "2026-08-26", "breaksTaken": 2, "watersLogged": 3,
          "focusMinutes": 60, "focusWarnings": 1
        },
        "2026-08-27": {
          "date": "2026-08-27", "breaksTaken": 4, "watersLogged": 6,
          "focusMinutes": 120, "focusWarnings": 2
        }
      },
      "petPosition": {
        "x": 820, "y": 410, "displayId": 2, "relativeX": 0.42, "relativeY": 0.87
      },
      "petHiddenByUser": true
    }
    """

    @Test("a realistic legacy store imports settings, stats, position and hidden flag")
    func importsRealisticStore() throws {
        let (persistence, directory, cleanup) = makePersistence()
        defer { cleanup() }

        let url = LegacyMigration.legacyStoreURL(in: directory)
        try Data(Self.realisticStore.utf8).write(to: url)

        #expect(LegacyMigration.run(into: persistence))

        let settings = persistence.settings
        #expect(settings.petAppearanceID == .xiaoJiMao)
        #expect(settings.breakIntervalMinutes == 30)
        #expect(settings.breakRunDurationSeconds == 45)
        #expect(!settings.hydrationReminderEnabled)
        #expect(settings.hydrationIntervalMinutes == 120)
        #expect(settings.focusDurationMinutes == 50)
        #expect(settings.distractionDetectionEnabled)
        #expect(settings.distractionGraceSeconds == 12)
        #expect(settings.distractionBlockedApps == ["Steam"])
        #expect(settings.distractionBlockedKeywords == ["youtube", "reddit"])
        #expect(settings.onboardingDismissed)
        #expect(settings.launchAtLoginEnabled)

        #expect(persistence.petHiddenByUser)
        #expect(persistence.petPosition?.displayId == 2)
        #expect(persistence.petPosition?.relativeX == 0.42)

        #expect(persistence.statsHistory.count == 2)
        #expect(persistence.statsHistory["2026-08-26"]?.breaksTaken == 2)
        #expect(persistence.currentStats.date == "2026-08-27")
        #expect(persistence.currentStats.focusMinutes == 120)
    }

    @Test("migration runs at most once")
    func migrationIsIdempotent() throws {
        let (persistence, directory, cleanup) = makePersistence()
        defer { cleanup() }

        let url = LegacyMigration.legacyStoreURL(in: directory)
        try Data(Self.realisticStore.utf8).write(to: url)

        #expect(LegacyMigration.run(into: persistence))
        #expect(persistence.hasMigratedLegacyStore)

        // A later local change must not be overwritten by a second run.
        var settings = persistence.settings
        settings.breakIntervalMinutes = 15
        persistence.settings = settings

        #expect(!LegacyMigration.run(into: persistence), "second run should be a no-op")
        #expect(persistence.settings.breakIntervalMinutes == 15)
    }

    @Test("an absent legacy file leaves defaults in place and does not retry")
    func absentFileDegradesToDefaults() {
        let (persistence, _, cleanup) = makePersistence()
        defer { cleanup() }

        #expect(!LegacyMigration.run(into: persistence))
        #expect(persistence.settings == Settings.defaults)
        #expect(persistence.hasMigratedLegacyStore, "must not retry on every launch")
    }

    @Test("malformed JSON degrades to defaults without crashing")
    func malformedFileDegradesToDefaults() throws {
        let (persistence, directory, cleanup) = makePersistence()
        defer { cleanup() }

        let url = LegacyMigration.legacyStoreURL(in: directory)
        try Data("{ this is not json ".utf8).write(to: url)

        #expect(!LegacyMigration.run(into: persistence))
        #expect(persistence.settings == Settings.defaults)
        #expect(persistence.hasMigratedLegacyStore)
    }

    @Test("a partial legacy store imports only what is present")
    func partialStore() throws {
        let (persistence, directory, cleanup) = makePersistence()
        defer { cleanup() }

        let url = LegacyMigration.legacyStoreURL(in: directory)
        try Data(#"{"petHiddenByUser":true}"#.utf8).write(to: url)

        #expect(LegacyMigration.run(into: persistence))
        #expect(persistence.petHiddenByUser)
        #expect(persistence.settings == Settings.defaults)
        #expect(persistence.petPosition == nil)
    }

    @Test("an empty JSON object imports nothing")
    func emptyObject() throws {
        let (persistence, directory, cleanup) = makePersistence()
        defer { cleanup() }

        let url = LegacyMigration.legacyStoreURL(in: directory)
        try Data("{}".utf8).write(to: url)

        #expect(!LegacyMigration.run(into: persistence))
        #expect(persistence.hasMigratedLegacyStore)
    }

    @Test("a legacy custom pet with invalid assets falls back to the default pet")
    func invalidCustomPetFallsBack() throws {
        let (persistence, directory, cleanup) = makePersistence()
        defer { cleanup() }

        let json = """
        {"settings":{"petAppearanceId":"custom","customPetAppearance":{
          "name":"Mine","assets":{"idle":{"relativePath":"/tmp/evil.gif",
          "originalName":"evil.gif","updatedAt":1}}}}}
        """
        let url = LegacyMigration.legacyStoreURL(in: directory)
        try Data(json.utf8).write(to: url)

        #expect(LegacyMigration.run(into: persistence))
        #expect(persistence.settings.petAppearanceID == Settings.defaults.petAppearanceID)
        #expect(persistence.settings.customPetAppearance == nil)
    }

    @Test("the legacy store path matches the Electron store name")
    func legacyStorePath() {
        let url = LegacyMigration.legacyStoreURL(in: URL(fileURLWithPath: "/tmp/x"))
        #expect(url.lastPathComponent == "deskpet.json")
    }

    @Test("stats history is merged with the current day")
    func statsMergedWithCurrentDay() {
        let (persistence, _, cleanup) = makePersistence()
        defer { cleanup() }

        let payload = LegacyMigration.Payload(
            settings: nil,
            stats: DayStats(date: "2026-08-28", breaksTaken: 1),
            statsHistory: ["2026-08-20": DayStats(date: "2026-08-20", breaksTaken: 9)],
            petPosition: nil,
            petHiddenByUser: nil
        )
        LegacyMigration.apply(payload, to: persistence)

        #expect(persistence.statsHistory.count == 2)
        #expect(persistence.statsHistory["2026-08-20"]?.breaksTaken == 9)
        #expect(persistence.statsHistory["2026-08-28"]?.breaksTaken == 1)
        #expect(persistence.currentStats.date == "2026-08-28")
    }
}

@Suite("Stats date keys")
struct StatsDateTests {

    @Test("keys are zero-padded ISO-style dates")
    func keyFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 7
        let date = calendar.date(from: components)!

        #expect(StatsDate.key(for: date, calendar: calendar) == "2026-03-07")
    }

    @Test("keys follow the local calendar day, not UTC")
    func keyUsesLocalDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!

        // 2026-08-27 19:00 UTC is already 2026-08-28 00:30 in Kolkata.
        let date = Date(timeIntervalSince1970: 1_787_857_200)
        let key = StatsDate.key(for: date, calendar: calendar)
        #expect(key.hasPrefix("2026-"))
        #expect(key.count == 10)
    }
}
