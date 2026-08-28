import Foundation

/// User-facing text, transcribed from the English bundle in `i18n.ts`.
///
/// The i18n indirection was dropped in the rewrite (the app was already
/// English-only), but the randomized message variants are preserved: the pet
/// picked a different phrasing each time, which is part of its character.
public enum Strings {

    /// Ported from `pick`: uniform choice, deliberately non-cryptographic.
    public static func pick(_ items: [String]) -> String {
        items.randomElement() ?? ""
    }

    /// Label on the focus countdown badge (`settings.focus` in the original).
    public static let focusBadgeLabel = "Focus"

    // MARK: - Menu

    public enum Menu {
        public static let showPet = "Show Pet"
        public static let hidePet = "Hide Pet"
        public static let startFocusMode = "Start Focus Mode"
        public static let stopFocusMode = "Stop Focus Mode"
        public static let settings = "Settings"
        public static let resetToday = "Reset Today"
        public static let quit = "Quit"

        public static let demoBreakReminder = "Demo: Break Reminder"
        public static let demoHydrationReminder = "Demo: Hydration Reminder"
        public static let demoFocusWarning = "Demo: Distraction Nudge"
        public static let demoHappyReaction = "Demo: Happy Reaction"
        public static let debugCycleStates = "Debug: Cycle Pet States"
    }

    // MARK: - Bubble actions

    public enum Actions {
        public static let breakDone = "I stood up"
        public static let breakRunDone = "I'm back"
        public static let breakSnooze = "Remind in 10 min"
        public static let breakMute = "Leave me today"
        public static let hydrationDone = "I drank water"
        public static let hydrationSnooze = "Remind later"
        public static let focusBack = "Back to work"
        public static let focusEnd = "End Focus"
        public static let openReleaseNotes = "Open Releases"
    }

    // MARK: - Settings window

    /// Transcribed from the `settings` bundle in `i18n.ts`.
    public enum SettingsLabels {
        public static let title = "Settings"
        public static let appearance = "Appearance"
        public static let petAppearance = "Pet"

        public static let reminders = "Reminders"
        public static let enableBreakReminder = "Enable Break Reminder"
        public static let breakInterval = "Break Interval"
        public static let breakRunDuration = "Break Duration"
        public static let enableHydrationReminder = "Enable Hydration Reminder"
        public static let hydrationInterval = "Hydration Interval"

        public static let focus = "Focus"
        public static let focusDuration = "Focus Duration"
        public static let startFocus = "Start Focus"
        public static let stopFocus = "Stop Focus"
        public static let enableDistractionDetection = "Enable Distraction Detection"
        public static let detectionGrace = "Detection Grace"
        public static let blockedApps = "Blocked Apps"
        public static let blockedKeywords = "Blocked Keywords"

        public static let detectionStatus = "Status"
        public static let accessibilityHelp =
            "DeskPet needs Accessibility permission to read the active window's "
            + "title. Grant it in System Settings › Privacy & Security › "
            + "Accessibility, then re-enable detection."
        public static let grantAccessibility = "Request Permission"
        public static let openPrivacySettings = "Open Privacy Settings"

        public static func detectionStateName(_ state: DistractionStatus.State) -> String {
            switch state {
            case .idle: return "Off"
            case .watching: return "Watching"
            case .permissionNeeded: return "Permission needed"
            case .error: return "Error"
            }
        }
        public static let addListItem = "Add…"
        public static func removeListItem(_ entry: String) -> String { "Remove \(entry)" }

        public static let system = "System"
        public static let launchAtLogin = "Launch at Login"
        public static let launchAtLoginHelp =
            "Packaged macOS and Windows builds will start after login. "
            + "Development builds only save the preference."
        public static let updates = "Updates"
        public static let checkForUpdates = "Check for Updates"
        public static let updateCheckOnLaunch = "Check Updates on Launch"
        public static let updateCheckOnLaunchHelp =
            "When enabled, DeskPet checks the latest GitHub Release on startup. "
            + "Otherwise it only checks when you ask."
        public static let updateIdle = "Updates have not been checked yet."
        public static let updateChecking = "Checking GitHub Releases…"
        public static func updateAvailable(_ version: String) -> String {
            "Version \(version) is available."
        }
        public static func updateCurrent(_ version: String) -> String {
            "You are on the latest version \(version)."
        }
        public static func updateError(_ message: String) -> String {
            "Update check failed: \(message)"
        }

        public static let customPet = "Custom"
        public static let customPetAssets = "Custom Assets"
        public static let customPetRequirements =
            "GIF only; the default state asset is required and other states are optional; "
            + "transparent backgrounds and consistent subject size are recommended"
        public static let customPetReady = "Ready"
        public static let customPetMissingRequired = "Default state asset required"
        public static let customPetRequired = "Required"
        public static let customPetOptional = "Optional"
        public static let uploadGif = "Upload GIF"
        public static let replaceGif = "Replace GIF"
        public static let removeGif = "Remove"
        public static let referenceAsset = "Reference"

        public static let today = "Today"
        public static let breaks = "Breaks"
        public static let waters = "Waters"
        public static let focusMinutes = "Focus"
        public static let warnings = "Distractions"
        public static let resetToday = "Reset Today"
        public static let history = "History"

        public static let about = "About"
        public static let version = "Version"
        public static let releaseNotes = "Release Notes"
        public static let openReleaseNotes = "Open Releases"

        public static let minuteUnit = "min"
        public static let secondUnit = "s"

        /// Display names for each pet state, used by the custom pet editor.
        public static func stateName(_ state: PetState) -> String {
            switch state {
            case .idle: return "Idle"
            case .sitting: return "Sitting"
            case .happy: return "Happy"
            case .breakPrompt: return "Break Prompt"
            case .breakRunning: return "Break Running"
            case .breakDone: return "Break Done"
            case .hydrationPrompt: return "Water Prompt"
            case .drinking: return "Drinking"
            case .hydrationDone: return "Water Done"
            case .focusGuard: return "Focus Guard"
            case .focusAlert: return "Focus Alert"
            case .focusDone: return "Focus Done"
            case .sad: return "Sad"
            case .sleeping: return "Sleeping"
            }
        }
    }

    // MARK: - Bubble messages

    public enum Bubble {
        public static let woof = ["woof!", "bark bark!", "arf~"]

        public static let breakReminder = [
            "You've been sitting too long, walk for a minute!",
            "I wanna play with you~ walk for a minute!",
            "Sitting for so long… go walk for a minute!",
            "I wanna play! Walk for a minute~"
        ]

        public static let breakRunComplete = [
            "Done playing~ sitting back down with you",
            "I'm back! Was waiting for you~",
            "Break's over, all settled down~"
        ]

        public static let breakIgnore = [
            "Okay… but I'll worry about you",
            "Hmm… you have to stand up next time",
            "Fine, I'll lie here and wait…"
        ]

        public static let hydrationReminder = [
            "I'm a little thirsty… you should drink some water too?",
            "I want water! You have some too~",
            "*licks lips* …time for water~",
            "My bowl's empty! Where's your cup?"
        ]

        public static let hydrationDone = [
            "*slurp slurp* ahh~",
            "All full!",
            "Woof, water's so good"
        ]

        public static let focusComplete = [
            "Focus time's up!",
            "Focus done! *tail wag*"
        ]

        public static let focusCancelled = [
            "Okay, I'll keep you company for a bit",
            "All done! I'm lying down~"
        ]

        public static let focusBack = [
            "Good, I'll keep watching~",
            "Mm! Back to work then",
            "I'll keep focusing too~"
        ]

        /// Variants that interpolate a value. Each closure corresponds to one
        /// phrasing in the original array.
        public static let breakRun: [(Int) -> String] = [
            { "I still wanna play for \($0)s! Get away from the screen~" },
            { "\($0)s left, no sneaking back!" },
            { "\($0)s!" }
        ]

        public static let focusStart: [(Int) -> String] = [
            { "Okay, I'll keep watch for \($0) minutes!" },
            { "Focus for \($0) minutes, I'm watching" }
        ]

        public static let focusWarning: [(String) -> String] = [
            { "Hey, no \($0)! We said we'd focus!" },
            { "I saw you open \($0)~ come back!" },
            { "Stay away from \($0)!" }
        ]

        public static let updateAvailable: [(String) -> String] = [
            { "Version \($0) is available. Want to see what's new?" },
            { "DeskPet has a new version: \($0)." }
        ]

        /// Picks one interpolating variant and applies it.
        public static func pick<Value>(_ variants: [(Value) -> String], _ value: Value) -> String {
            guard let variant = variants.randomElement() else { return "" }
            return variant(value)
        }
    }
}
