import Foundation

/// Settings and window state in `UserDefaults`; stats history in a JSON file.
///
/// Replaces `electron-store`. See ADR-4 for why the two shapes are stored
/// differently.
public final class Persistence {
    enum Key {
        static let settings = "settings"
        static let petPosition = "petPosition"
        static let petHiddenByUser = "petHiddenByUser"
        static let migratedLegacyStore = "migratedLegacyStore"
    }

    private let defaults: UserDefaults
    /// Directory holding `stats.json` and `custom_pet_assets/`.
    public let supportDirectory: URL

    public init(
        defaults: UserDefaults = .standard,
        supportDirectory: URL = PetAssetLoader.applicationSupportRoot
    ) {
        self.defaults = defaults
        self.supportDirectory = supportDirectory
    }

    // MARK: - Settings

    /// Always normalized on the way in and out, so a hand-edited or migrated
    /// payload cannot put the app into an invalid state.
    public var settings: Settings {
        get {
            guard let data = defaults.data(forKey: Key.settings),
                  let decoded = try? JSONDecoder().decode(Settings.self, from: data)
            else {
                return Settings.defaults
            }
            return decoded.normalized()
        }
        set {
            let normalized = newValue.normalized()
            guard let data = try? JSONEncoder().encode(normalized) else { return }
            defaults.set(data, forKey: Key.settings)
        }
    }

    // MARK: - Pet window state

    public var petPosition: SavedWindowPosition? {
        get {
            guard let data = defaults.data(forKey: Key.petPosition) else { return nil }
            return try? JSONDecoder().decode(SavedWindowPosition.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                defaults.removeObject(forKey: Key.petPosition)
                return
            }
            defaults.set(data, forKey: Key.petPosition)
        }
    }

    /// Whether the user explicitly hid the pet, which survives relaunch.
    public var petHiddenByUser: Bool {
        get { defaults.bool(forKey: Key.petHiddenByUser) }
        set { defaults.set(newValue, forKey: Key.petHiddenByUser) }
    }

    // MARK: - Migration flag

    public var hasMigratedLegacyStore: Bool {
        get { defaults.bool(forKey: Key.migratedLegacyStore) }
        set { defaults.set(newValue, forKey: Key.migratedLegacyStore) }
    }

    // MARK: - Stats file

    public var statsFileURL: URL {
        supportDirectory.appendingPathComponent("stats.json")
    }

    var statsFile: StatsFile {
        get {
            guard let data = try? Data(contentsOf: statsFileURL),
                  let decoded = try? JSONDecoder().decode(StatsFile.self, from: data)
            else {
                // An empty date deliberately: this store is dumb about time, and
                // `StatsStore` decides which day is current from its injected
                // clock. `saveToHistory` skips dateless entries, so an untouched
                // install cannot archive a phantom day.
                return StatsFile(current: .empty(date: ""), history: [:])
            }
            return decoded
        }
        set {
            do {
                try FileManager.default.createDirectory(
                    at: supportDirectory, withIntermediateDirectories: true
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(newValue).write(to: statsFileURL, options: .atomic)
            } catch {
                NSLog("DeskPet: failed to write stats.json: \(error)")
            }
        }
    }

    /// Convenience accessors; Task 14 layers date rollover on top.
    public var currentStats: DayStats {
        get { statsFile.current }
        set {
            var file = statsFile
            file.current = newValue
            file.history[newValue.date] = newValue
            statsFile = file
        }
    }

    public var statsHistory: StatsHistory {
        get { statsFile.history }
        set {
            var file = statsFile
            file.history = newValue
            statsFile = file
        }
    }

    /// Removes everything this instance owns. Used by tests.
    func reset() {
        for key in [Key.settings, Key.petPosition, Key.petHiddenByUser, Key.migratedLegacyStore] {
            defaults.removeObject(forKey: key)
        }
        try? FileManager.default.removeItem(at: statsFileURL)
    }
}
