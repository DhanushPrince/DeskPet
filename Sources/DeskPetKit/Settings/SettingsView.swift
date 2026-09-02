import AppKit
import SwiftUI

/// Colours transcribed from the settings window's stylesheet.
enum SettingsStyle {
    /// `backgroundColor: "#faf6ee"` on the Electron BrowserWindow.
    static let background = Color(red: 250 / 255, green: 246 / 255, blue: 238 / 255)
    static let cardBackground = Color(red: 255 / 255, green: 252 / 255, blue: 244 / 255)
    static let cardBorder = Color(red: 76 / 255, green: 57 / 255, blue: 39 / 255, opacity: 0.14)
    static let primaryText = Color(red: 59 / 255, green: 48 / 255, blue: 37 / 255)
    static let accent = Color(red: 36 / 255, green: 78 / 255, blue: 69 / 255)

    static let sectionSpacing: CGFloat = 18
    static let cardPadding: CGFloat = 16
    static let cardRadius: CGFloat = 12
}

/// The settings window's content.
///
/// SwiftUI here (ADR-1's split): this is ordinary form UI with no transparency
/// or hit-testing requirements, so it gains from SwiftUI's layout while the pet
/// window stays AppKit. State flows through the `@Observable` `AppState`, so
/// edits reach the running pet with no extra plumbing.
public struct SettingsView: View {
    @Bindable var state: AppState
    @State private var customEditorOpen = false

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsStyle.sectionSpacing) {
                appearanceSection
                remindersSection
                focusSection
                systemSection
                todaySection
                aboutSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsStyle.background)
        .foregroundStyle(SettingsStyle.primaryText)
        .tint(SettingsStyle.accent)
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        SettingsCard(title: Strings.SettingsLabels.appearance) {
            Picker(Strings.SettingsLabels.petAppearance, selection: appearanceBinding) {
                ForEach(PetAppearances.displayOrder, id: \.self) { id in
                    Text(PetAppearances.manifest(id).label).tag(PetAppearanceID(
                        rawValue: id.rawValue
                    ) ?? .lineDog)
                }
                if PetAppearances.hasRequiredAssets(state.settings.customPetAppearance) {
                    Text(state.settings.customPetAppearance?.name ?? "Custom")
                        .tag(PetAppearanceID.custom)
                }
            }
            .pickerStyle(.radioGroup)

            // Tappable previews — the radio group alone is easy to miss; Electron
            // also let you pick by clicking the pet cards.
            HStack(spacing: 12) {
                ForEach(PetAppearances.displayOrder, id: \.self) { id in
                    let appearanceID = PetAppearanceID(rawValue: id.rawValue) ?? .lineDog
                    Button {
                        selectAppearance(appearanceID)
                    } label: {
                        VStack(spacing: 6) {
                            PetPreview(appearance: appearanceID, custom: nil)
                            Text(PetAppearances.manifest(id).label)
                                .font(.caption)
                        }
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(state.settings.petAppearanceID == appearanceID
                                      ? SettingsStyle.accent.opacity(0.10)
                                      : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
                if PetAppearances.hasRequiredAssets(state.settings.customPetAppearance) {
                    Button {
                        selectAppearance(.custom)
                    } label: {
                        VStack(spacing: 6) {
                            PetPreview(appearance: .custom, custom: state.settings.customPetAppearance)
                            Text(state.settings.customPetAppearance?.name
                                 ?? Strings.SettingsLabels.customPet)
                                .font(.caption)
                        }
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(state.settings.petAppearanceID == .custom
                                      ? SettingsStyle.accent.opacity(0.10)
                                      : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            DisclosureGroup(isExpanded: $customEditorOpen) {
                CustomPetEditor(state: state)
            } label: {
                Text(Strings.SettingsLabels.customPetAssets)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var appearanceBinding: Binding<PetAppearanceID> {
        Binding(
            get: { state.settings.petAppearanceID },
            set: { next in selectAppearance(next) }
        )
    }

    private func selectAppearance(_ id: PetAppearanceID) {
        state.updateSettings { $0.petAppearanceID = id }
    }

    // MARK: Reminders

    private var remindersSection: some View {
        SettingsCard(title: Strings.SettingsLabels.reminders) {
            Toggle(Strings.SettingsLabels.enableBreakReminder, isOn: boolBinding(
                get: { $0.breakReminderEnabled },
                set: { $0.breakReminderEnabled = $1 }
            ))

            NumberRow(
                label: Strings.SettingsLabels.breakInterval,
                unit: Strings.SettingsLabels.minuteUnit,
                range: SettingsLimits.breakIntervalMinutes,
                value: intBinding(
                    get: { $0.breakIntervalMinutes },
                    set: { $0.breakIntervalMinutes = $1 },
                    range: SettingsLimits.breakIntervalMinutes
                )
            )
            .disabled(!state.settings.breakReminderEnabled)

            NumberRow(
                label: Strings.SettingsLabels.breakRunDuration,
                unit: Strings.SettingsLabels.secondUnit,
                range: SettingsLimits.breakRunDurationSeconds,
                value: intBinding(
                    get: { $0.breakRunDurationSeconds },
                    set: { $0.breakRunDurationSeconds = $1 },
                    range: SettingsLimits.breakRunDurationSeconds
                )
            )

            Divider()

            Toggle(Strings.SettingsLabels.enableHydrationReminder, isOn: boolBinding(
                get: { $0.hydrationReminderEnabled },
                set: { $0.hydrationReminderEnabled = $1 }
            ))

            NumberRow(
                label: Strings.SettingsLabels.hydrationInterval,
                unit: Strings.SettingsLabels.minuteUnit,
                range: SettingsLimits.hydrationIntervalMinutes,
                value: intBinding(
                    get: { $0.hydrationIntervalMinutes },
                    set: { $0.hydrationIntervalMinutes = $1 },
                    range: SettingsLimits.hydrationIntervalMinutes
                )
            )
            .disabled(!state.settings.hydrationReminderEnabled)
        }
    }

    // MARK: Focus

    private var focusSection: some View {
        SettingsCard(title: Strings.SettingsLabels.focus) {
            NumberRow(
                label: Strings.SettingsLabels.focusDuration,
                unit: Strings.SettingsLabels.minuteUnit,
                range: SettingsLimits.focusDurationMinutes,
                value: intBinding(
                    get: { $0.focusDurationMinutes },
                    set: { $0.focusDurationMinutes = $1 },
                    range: SettingsLimits.focusDurationMinutes
                )
            )

            if state.focusActive {
                Button(Strings.SettingsLabels.stopFocus) {
                    state.stopFocus(completed: false)
                }
            } else {
                Button(Strings.SettingsLabels.startFocus) {
                    state.startFocus()
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            Toggle(Strings.SettingsLabels.hidePetDuringMeetings, isOn: boolBinding(
                get: { $0.hidePetDuringMeetings },
                set: { $0.hidePetDuringMeetings = $1 }
            ))
            Text(Strings.SettingsLabels.hidePetDuringMeetingsHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(Strings.SettingsLabels.enableDistractionDetection, isOn: boolBinding(
                get: { $0.distractionDetectionEnabled },
                set: { $0.distractionDetectionEnabled = $1 }
            ))
            Text(Strings.SettingsLabels.browserAutomationHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            NumberRow(
                label: Strings.SettingsLabels.detectionGrace,
                unit: Strings.SettingsLabels.secondUnit,
                range: SettingsLimits.distractionGraceSeconds,
                value: intBinding(
                    get: { $0.distractionGraceSeconds },
                    set: { $0.distractionGraceSeconds = $1 },
                    range: SettingsLimits.distractionGraceSeconds
                )
            )
            .disabled(!state.settings.distractionDetectionEnabled)

            if state.settings.distractionDetectionEnabled {
                distractionStatusRow
            }

            EditableList(
                title: Strings.SettingsLabels.blockedApps,
                entries: listBinding(
                    get: { $0.distractionBlockedApps },
                    set: { $0.distractionBlockedApps = $1 }
                )
            )
            .disabled(!state.settings.distractionDetectionEnabled)

            EditableList(
                title: Strings.SettingsLabels.blockedKeywords,
                entries: listBinding(
                    get: { $0.distractionBlockedKeywords },
                    set: { $0.distractionBlockedKeywords = $1 }
                )
            )
            .disabled(!state.settings.distractionDetectionEnabled)
        }
    }

    /// What the detector currently sees, plus a route to fix a missing
    /// permission.
    private var distractionStatusRow: some View {
        let status = state.distractionStatus
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Strings.SettingsLabels.detectionStatus)
                    .font(.caption.weight(.semibold))
                Text(Strings.SettingsLabels.detectionStateName(status.state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if status.state == .permissionNeeded {
                Text(Strings.SettingsLabels.accessibilityHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(Strings.SettingsLabels.grantAccessibility) {
                        ActiveWindowReader.requestPermission()
                    }
                    Button(Strings.SettingsLabels.openPrivacySettings) {
                        state.openAccessibilitySettings()
                    }
                }
            } else if !status.activeApp.isEmpty {
                Text(
                    status.activeWindowTitle.isEmpty
                        ? status.activeApp
                        : "\(status.activeApp) — \(status.activeWindowTitle)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            if let error = status.error, status.state == .error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: System

    private var systemSection: some View {
        SettingsCard(title: Strings.SettingsLabels.system) {
            Toggle(Strings.SettingsLabels.launchAtLogin, isOn: boolBinding(
                get: { $0.launchAtLoginEnabled },
                set: { $0.launchAtLoginEnabled = $1 }
            ))
            Text(Strings.SettingsLabels.launchAtLoginHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle(Strings.SettingsLabels.updateCheckOnLaunch, isOn: boolBinding(
                get: { $0.checkUpdatesOnLaunchEnabled },
                set: { $0.checkUpdatesOnLaunchEnabled = $1 }
            ))
            Text(Strings.SettingsLabels.updateCheckOnLaunchHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button(Strings.SettingsLabels.checkForUpdates) {
                    state.checkForUpdates()
                }
                if state.canInstallUpdate {
                    Button(Strings.SettingsLabels.updateNow) {
                        state.installReadyUpdate()
                    }
                }
                Text(state.updateStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Today

    private var todaySection: some View {
        SettingsCard(title: Strings.SettingsLabels.today) {
            HStack(spacing: 24) {
                StatTile(label: Strings.SettingsLabels.breaks, value: state.stats.breaksTaken)
                StatTile(label: Strings.SettingsLabels.waters, value: state.stats.watersLogged)
                StatTile(
                    label: Strings.SettingsLabels.focusMinutes,
                    value: state.stats.focusMinutes,
                    unit: Strings.SettingsLabels.minuteUnit
                )
                StatTile(label: Strings.SettingsLabels.warnings, value: state.stats.focusWarnings)
            }

            Button(Strings.SettingsLabels.resetToday) {
                state.resetTodayStats()
            }

            if !recentHistory.isEmpty {
                Divider()
                Text(Strings.SettingsLabels.history)
                    .font(.subheadline.weight(.semibold))
                ForEach(recentHistory, id: \.date) { day in
                    HStack {
                        Text(day.date)
                            .font(.caption.monospaced())
                        Spacer()
                        Text(
                            "\(day.breaksTaken) · \(day.watersLogged) · "
                                + "\(day.focusMinutes)\(Strings.SettingsLabels.minuteUnit) · "
                                + "\(day.focusWarnings)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Most recent days first, excluding today (shown above).
    private var recentHistory: [DayStats] {
        state.statsStore.history.values
            .filter { $0.date != state.stats.date && !$0.date.isEmpty }
            .sorted { $0.date > $1.date }
            .prefix(7)
            .map { $0 }
    }

    // MARK: About

    private var aboutSection: some View {
        SettingsCard(title: Strings.SettingsLabels.about) {
            HStack {
                Text(Strings.SettingsLabels.version)
                Spacer()
                Text(AppInfo.version).foregroundStyle(.secondary)
            }
            Button(Strings.SettingsLabels.openReleaseNotes) {
                NSWorkspace.shared.open(Constants.releasesURL)
            }
        }
    }

    // MARK: Bindings

    private func boolBinding(
        get: @escaping (Settings) -> Bool,
        set: @escaping (inout Settings, Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { get(state.settings) },
            set: { next in state.updateSettings { set(&$0, next) } }
        )
    }

    private func intBinding(
        get: @escaping (Settings) -> Int,
        set: @escaping (inout Settings, Int) -> Void,
        range: ClosedRange<Int>
    ) -> Binding<Int> {
        Binding(
            get: { get(state.settings) },
            set: { next in
                let clamped = SettingsLimits.clamp(next, to: range)
                state.updateSettings { set(&$0, clamped) }
            }
        )
    }

    private func listBinding(
        get: @escaping (Settings) -> [String],
        set: @escaping (inout Settings, [String]) -> Void
    ) -> Binding<[String]> {
        Binding(
            get: { get(state.settings) },
            set: { next in state.updateSettings { set(&$0, next) } }
        )
    }
}

// MARK: - Building blocks

/// A titled card, matching the settings window's grouped look.
struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(SettingsStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsStyle.cardRadius)
                .fill(SettingsStyle.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsStyle.cardRadius)
                .stroke(SettingsStyle.cardBorder, lineWidth: 1)
        )
    }
}

/// A labelled numeric field with a stepper, bounded to `range`.
struct NumberRow: View {
    let label: String
    let unit: String
    let range: ClosedRange<Int>
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: $value, format: .number)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Stepper("", value: $value, in: range)
                .labelsHidden()
        }
    }
}

/// An editable list of strings with add and remove controls.
struct EditableList: View {
    let title: String
    @Binding var entries: [String]
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            ForEach(entries, id: \.self) { entry in
                HStack {
                    Text(entry)
                    Spacer()
                    Button {
                        entries.removeAll { $0 == entry }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Strings.SettingsLabels.removeListItem(entry))
                }
            }

            HStack {
                TextField(Strings.SettingsLabels.addListItem, text: $draft)
                    .onSubmit(add)
                Button(Strings.SettingsLabels.addListItem, action: add)
                    .disabled(normalizedDraft.isEmpty)
            }
        }
    }

    private var normalizedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        let entry = normalizedDraft
        // Matching is case-insensitive, so treat differing cases as duplicates.
        guard !entry.isEmpty,
              !entries.contains(where: { $0.caseInsensitiveCompare(entry) == .orderedSame })
        else {
            draft = ""
            return
        }
        entries.append(entry)
        draft = ""
    }
}

/// One counter in the Today row.
struct StatTile: View {
    let label: String
    let value: Int
    var unit: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)\(unit)")
                .font(.title2.weight(.semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Still preview of an appearance's idle frame.
struct PetPreview: View {
    let appearance: PetAppearanceID
    let custom: CustomPetAppearance?
    var state: PetState = .idle
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let image = PetAssetLoader.previewImage(
                for: appearance, custom: custom, state: state
            ) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Per-state GIF slots for a custom appearance.
struct CustomPetEditor: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Strings.SettingsLabels.customPetRequirements)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Text(
                    PetAppearances.hasRequiredAssets(state.settings.customPetAppearance)
                        ? Strings.SettingsLabels.customPetReady
                        : Strings.SettingsLabels.customPetMissingRequired
                )
                .font(.caption.weight(.semibold))
            }

            ForEach(PetState.allCases, id: \.self) { petState in
                customRow(petState)
            }
        }
    }

    private func customRow(_ petState: PetState) -> some View {
        let asset = state.settings.customPetAppearance?.assets[petState]
        let required = PetAppearances.requiredCustomStates.contains(petState)
        return HStack(alignment: .center, spacing: 10) {
            PetPreview(appearance: .lineDog, custom: nil, state: petState, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Strings.SettingsLabels.stateName(petState))
                        .font(.caption.weight(.semibold))
                    Text(
                        required
                            ? Strings.SettingsLabels.customPetRequired
                            : Strings.SettingsLabels.customPetOptional
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                if let name = asset?.originalName {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            PetPreview(
                appearance: asset == nil ? .lineDog : .custom,
                custom: state.settings.customPetAppearance,
                state: petState,
                size: 40
            )
            .opacity(asset == nil ? 0.25 : 1)

            if asset == nil {
                Button(Strings.SettingsLabels.uploadGif) {
                    state.chooseCustomAsset(for: petState)
                }
            } else {
                Button(Strings.SettingsLabels.replaceGif) {
                    state.chooseCustomAsset(for: petState)
                }
                Button(Strings.SettingsLabels.removeGif) {
                    state.removeCustomAsset(for: petState)
                }
            }
        }
    }
}
