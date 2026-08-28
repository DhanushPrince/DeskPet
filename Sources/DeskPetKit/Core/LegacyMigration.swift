import Foundation

/// One-time import of the Electron build's `electron-store` file.
///
/// The native app uses the same Application Support directory, so
/// `custom_pet_assets/` is reused in place and only the JSON payload needs
/// translating. Runs at most once, guarded by a flag in `UserDefaults`.
public enum LegacyMigration {
    /// Decoded contents of `deskpet.json`. Every field is optional because the
    /// file may predate any given key.
    public struct Payload: Equatable {
        public var settings: Settings?
        public var stats: DayStats?
        public var statsHistory: StatsHistory?
        public var petPosition: SavedWindowPosition?
        public var petHiddenByUser: Bool?

        public var isEmpty: Bool {
            settings == nil && stats == nil && statsHistory == nil
                && petPosition == nil && petHiddenByUser == nil
        }
    }

    /// `~/Library/Application Support/DeskPet/deskpet.json`, matching
    /// electron-store's `name: "deskpet"`.
    public static func legacyStoreURL(
        in directory: URL = PetAssetLoader.applicationSupportRoot
    ) -> URL {
        directory.appendingPathComponent("\(Constants.legacyStoreName).json")
    }

    /// Top-level keys of the electron-store schema.
    private struct Envelope: Decodable {
        var settings: Settings?
        var stats: DayStats?
        var statsHistory: StatsHistory?
        var petPosition: SavedWindowPosition?
        var petHiddenByUser: Bool?
    }

    /// Decodes a payload, tolerating malformed or partial JSON.
    public static func decode(_ data: Data) -> Payload {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return Payload()
        }
        return Payload(
            settings: envelope.settings,
            stats: envelope.stats,
            statsHistory: envelope.statsHistory,
            petPosition: envelope.petPosition,
            petHiddenByUser: envelope.petHiddenByUser
        )
    }

    /// Imports the legacy store into `persistence` if it has not run before.
    ///
    /// - Returns: true when data was imported. A missing or unreadable file
    ///   still marks the migration complete, so it is never retried.
    @discardableResult
    public static func run(
        into persistence: Persistence,
        from url: URL? = nil
    ) -> Bool {
        guard !persistence.hasMigratedLegacyStore else { return false }

        let source = url ?? legacyStoreURL(in: persistence.supportDirectory)
        defer { persistence.hasMigratedLegacyStore = true }

        guard let data = try? Data(contentsOf: source) else {
            NSLog("DeskPet: no legacy store at \(source.path), starting with defaults")
            return false
        }

        let payload = decode(data)
        guard !payload.isEmpty else {
            NSLog("DeskPet: legacy store at \(source.path) had nothing to import")
            return false
        }

        apply(payload, to: persistence)
        NSLog("DeskPet: migrated legacy store from \(source.path)")
        return true
    }

    /// Applies a decoded payload. Separate from `run` so tests can exercise it
    /// without touching the migration flag.
    public static func apply(_ payload: Payload, to persistence: Persistence) {
        if let settings = payload.settings {
            // Normalization drops a custom appearance whose GIFs no longer
            // validate, falling back to the default pet.
            persistence.settings = settings
        }
        if let position = payload.petPosition {
            persistence.petPosition = position
        }
        if let hidden = payload.petHiddenByUser {
            persistence.petHiddenByUser = hidden
        }

        // Stats: merge history first, then let the current day overwrite its own
        // entry so the two views agree.
        var history = payload.statsHistory ?? [:]
        if let stats = payload.stats {
            history[stats.date] = stats
        }
        guard !history.isEmpty else { return }

        let current = payload.stats ?? .empty(date: StatsDate.key())
        persistence.statsFile = StatsFile(current: current, history: history)
    }
}
