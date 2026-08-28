import Foundation

/// Where an asset path is rooted.
public enum PetAssetSource: Equatable, Sendable {
    /// Relative to the bundled `PetAssets` resource directory.
    case bundled
    /// Relative to the app's Application Support directory
    /// (i.e. `custom_pet_assets/<state>/<file>.gif`).
    case custom
}

/// One resolved animation for a state. `paths` holds every variant; the
/// Electron source modelled this as `string | string[]` and normalized at each
/// use site, so it is normalized to an array here instead.
public struct PetAssetDefinition: Equatable, Sendable {
    public let paths: [String]
    public let source: PetAssetSource
    /// True when this asset is standing in for a state that has no artwork of
    /// its own. Surfaced in settings so users can see which states are covered.
    public let isPlaceholder: Bool
    /// When set, the animation plays once and is re-triggered on this interval
    /// instead of looping continuously.
    public let replayIntervalMs: Int?

    public init(
        paths: [String],
        source: PetAssetSource = .bundled,
        isPlaceholder: Bool = false,
        replayIntervalMs: Int? = nil
    ) {
        self.paths = paths
        self.source = source
        self.isPlaceholder = isPlaceholder
        self.replayIntervalMs = replayIntervalMs
    }
}

public struct PetAppearanceManifest: Sendable {
    public let id: BuiltInPetAppearanceID
    public let label: String
    /// Directory name under `Resources/PetAssets`. Transliterated to ASCII
    /// during the rewrite; GIF filenames are unchanged.
    public let folder: String
    /// Used when a state has neither its own asset nor a fallback state asset.
    public let fallback: PetAssetDefinition
    public let states: [PetState: PetAssetDefinition]
}

// MARK: - Custom appearances

public struct CustomPetAsset: Equatable, Codable, Sendable {
    public let relativePath: String
    public let originalName: String
    public let updatedAt: Double

    public init(relativePath: String, originalName: String, updatedAt: Double) {
        self.relativePath = relativePath
        self.originalName = originalName
        self.updatedAt = updatedAt
    }
}

public struct CustomPetAppearance: Equatable, Codable, Sendable {
    public var name: String
    public var assets: [PetState: CustomPetAsset]

    public init(name: String, assets: [PetState: CustomPetAsset]) {
        self.name = name
        self.assets = assets
    }
}

// MARK: - Registry

public enum PetAppearances {
    /// States that borrow another state's artwork when they have none of their
    /// own. Ported from `STATE_FALLBACKS`.
    public static let stateFallbacks: [PetState: PetState] = [
        .breakDone: .happy,
        .hydrationDone: .happy,
        .focusDone: .happy
    ]

    /// A custom appearance is only usable once these states have artwork.
    public static let requiredCustomStates: [PetState] = [.idle]

    /// Declaration order matches `Object.values(PET_APPEARANCES)` in the
    /// Electron source, which is the order the settings picker showed.
    public static let all: [BuiltInPetAppearanceID: PetAppearanceManifest] = [
        .lovartPuppy: goldenPuppy,
        .lineDog: lineDog,
        .xiaoJiMao: xiaoJiMao
    ]

    public static let displayOrder: [BuiltInPetAppearanceID] = [.lovartPuppy, .lineDog, .xiaoJiMao]

    public static func manifest(_ id: BuiltInPetAppearanceID) -> PetAppearanceManifest {
        // Force-unwrap is safe: `all` is a compile-time-complete map over the
        // enum, and `displayOrderCoversAllAppearances` in the test suite guards
        // against a case being added without a manifest.
        all[id]!
    }

    /// Options for the settings picker, in display order.
    public static func options() -> [(value: BuiltInPetAppearanceID, label: String)] {
        displayOrder.map { (value: $0, label: manifest($0).label) }
    }

    // MARK: Resolution

    /// Three-level resolution, ported from `getPetAssetDefinition`:
    /// exact state → fallback state → appearance-wide fallback.
    public static func assetDefinition(
        appearance: PetAppearanceID,
        state: PetState,
        custom: CustomPetAppearance? = nil
    ) -> PetAssetDefinition {
        if appearance == .custom, let customAsset = customAssetDefinition(custom, state) {
            return customAsset
        }

        let manifest = manifest(appearance.builtIn)
        if let exact = manifest.states[state] {
            return exact
        }
        if let fallbackState = stateFallbacks[state], let borrowed = manifest.states[fallbackState] {
            // Returned unchanged, matching `getPetAssetDefinition`: the
            // borrowed definition keeps its own `isPlaceholder` value rather
            // than being marked as a placeholder by virtue of being borrowed.
            return borrowed
        }
        return manifest.fallback
    }

    /// Ported from `getCustomPetAssetDefinition`.
    public static func customAssetDefinition(
        _ custom: CustomPetAppearance?,
        _ state: PetState
    ) -> PetAssetDefinition? {
        guard let custom, hasRequiredAssets(custom) else { return nil }

        let exact = custom.assets[state]
        let fallbackState = stateFallbacks[state]
        let resolved = exact
            ?? fallbackState.flatMap { custom.assets[$0] }
            ?? custom.assets[.idle]
        guard let resolved else { return nil }

        return PetAssetDefinition(
            paths: [resolved.relativePath],
            source: .custom,
            isPlaceholder: resolved.relativePath != exact?.relativePath
        )
    }

    /// Ported from `hasRequiredCustomPetAssets`.
    public static func hasRequiredAssets(_ custom: CustomPetAppearance?) -> Bool {
        guard let custom else { return false }
        return requiredCustomStates.allSatisfy { custom.assets[$0] != nil }
    }
}

// MARK: - Manifest data

private extension PetAppearances {
    /// Builds a bundled definition. `stateFolder` is explicit because several
    /// states borrow another state's directory (for example Line Dog's
    /// `sitting`, which points at `idle`).
    static func bundled(
        _ folder: String,
        _ stateFolder: PetState,
        _ names: [String],
        placeholder: Bool = false,
        replayIntervalMs: Int? = nil
    ) -> PetAssetDefinition {
        PetAssetDefinition(
            paths: names.map { "\(folder)/\(stateFolder.rawValue)/\($0)" },
            source: .bundled,
            isPlaceholder: placeholder,
            replayIntervalMs: replayIntervalMs
        )
    }

    // MARK: Golden Puppy

    static var goldenPuppy: PetAppearanceManifest {
        let f = "GoldenPuppy"
        return PetAppearanceManifest(
            id: .lovartPuppy,
            label: "Golden Puppy (beta)",
            folder: f,
            fallback: bundled(f, .idle, ["standing pose.gif"], placeholder: true),
            states: [
                .idle: bundled(f, .idle, [
                    "standing pose.gif",
                    "standing pose2.gif",
                    "standing pose3.gif"
                ]),
                .sitting: bundled(f, .sitting, ["3 - welcome to work.gif"]),
                .happy: bundled(f, .happy, [
                    "1 - waiting for playing outside.gif",
                    "3 - welcome to work.gif"
                ]),
                .breakPrompt: bundled(f, .breakPrompt, ["1 - waiting for playing outside.gif"]),
                .breakRunning: bundled(
                    f, .breakRunning, ["1 - playing outside.gif"],
                    replayIntervalMs: 4500
                ),
                .hydrationPrompt: bundled(f, .hydrationPrompt, ["want_water.gif"]),
                .drinking: bundled(f, .drinking, ["got_water.gif"]),
                .focusGuard: bundled(f, .focusGuard, ["standing pose4.gif"]),
                .focusAlert: bundled(f, .focusAlert, ["2 - standing reminder.gif"]),
                .sad: bundled(f, .sad, ["4 - sleeping.gif"], placeholder: true),
                .sleeping: bundled(f, .sleeping, ["4 - sleeping.gif"], placeholder: true)
                // breakDone / hydrationDone / focusDone resolve to `happy`.
            ]
        )
    }

    // MARK: Line Dog

    static var lineDog: PetAppearanceManifest {
        let f = "LineDog"
        return PetAppearanceManifest(
            id: .lineDog,
            label: "Line Dog",
            folder: f,
            fallback: bundled(f, .idle, ["线条小狗第9弹_甩耳朵.gif"], placeholder: true),
            states: [
                .idle: bundled(f, .idle, [
                    "线条小狗第12弹_无聊.gif",
                    "线条小狗第12弹_晃脚脚.gif",
                    "线条小狗第1弹_摆烂.gif",
                    "线条小狗第9弹_甩耳朵.gif"
                ]),
                .sitting: bundled(f, .idle, ["线条小狗第12弹_晃脚脚.gif"], placeholder: true),
                .happy: bundled(f, .happy, [
                    "线条小狗第1弹_嗨.gif",
                    "线条小狗第1弹_爱你.gif",
                    "线条小狗第8弹_好耶.gif"
                ]),
                .breakPrompt: bundled(f, .breakPrompt, [
                    "线条小狗第2弹_激动.gif",
                    "线条小狗第5弹_偷看.gif",
                    "线条小狗第5弹_出去玩.gif"
                ]),
                .breakRunning: bundled(f, .breakRunning, [
                    "线条小狗第1弹_啦啦啦.gif",
                    "线条小狗第1弹_来了.gif"
                ]),
                .breakDone: bundled(f, .breakDone, [
                    "线条小狗第11弹_骄傲.gif",
                    "线条小狗第12弹_送你心心.gif",
                    "线条小狗第2弹_耶.gif"
                ]),
                .hydrationPrompt: bundled(f, .hydrationPrompt, ["线条小狗第2弹_快点.gif"]),
                .drinking: bundled(f, .drinking, ["线条小狗第19弹_喝咖啡.gif"]),
                .hydrationDone: bundled(f, .hydrationDone, ["线条小狗第12弹_好棒.gif"]),
                .focusGuard: bundled(f, .focusGuard, [
                    "线条小狗第17弹_工作.gif",
                    "线条小狗第2弹_努力.gif",
                    "线条小狗第9弹_甩耳朵.gif"
                ]),
                .focusAlert: bundled(f, .focusAlert, [
                    "线条小狗第15弹_惊.gif",
                    "线条小狗第15弹_疑问.gif",
                    "线条小狗第1弹_什么.gif",
                    "线条小狗第1弹_哼.gif",
                    "线条小狗第3弹_不要.gif"
                ]),
                .focusDone: bundled(f, .focusDone, [
                    "线条小狗第1弹_庆祝.gif",
                    "线条小狗第2弹_庆祝.gif",
                    "线条小狗第3弹_好耶.gif"
                ]),
                .sad: bundled(f, .sad, [
                    "线条小狗第13弹_大哭.gif",
                    "线条小狗第15弹_呜呜呜.gif",
                    "线条小狗第8弹_伤心.gif",
                    "线条小狗第8弹_呜呜.gif"
                ]),
                .sleeping: bundled(f, .sleeping, ["线条小狗第12弹_困.gif"])
            ]
        )
    }

    // MARK: Xiao Ji Mao

    static var xiaoJiMao: PetAppearanceManifest {
        let f = "XiaoJiMao"
        return PetAppearanceManifest(
            id: .xiaoJiMao,
            label: "Xiao Ji Mao",
            folder: f,
            fallback: bundled(f, .idle, ["线条小狗第6弹_放松.gif"], placeholder: true),
            states: [
                .idle: bundled(f, .idle, [
                    "线条小狗第11弹_转圈.gif",
                    "线条小狗第6弹_放松.gif",
                    "线条小狗第6弹_晃脚脚.gif"
                ]),
                .sitting: bundled(f, .idle, ["线条小狗第6弹_晃脚脚.gif"], placeholder: true),
                .happy: bundled(f, .happy, [
                    "线条小狗第20弹_开心.gif",
                    "线条小狗第6弹_开心.gif"
                ]),
                .breakPrompt: bundled(f, .breakPrompt, [
                    "线条小狗第10弹_在.gif",
                    "线条小狗第10弹_摇尾巴.gif",
                    "线条小狗第9弹_甩.gif"
                ]),
                .breakRunning: bundled(f, .breakRunning, [
                    "线条小狗第14弹_摇摆.gif",
                    "线条小狗第8弹_贴贴.gif",
                    "线条小狗第9弹_加油.gif"
                ]),
                .breakDone: bundled(f, .breakDone, [
                    "线条小狗第18弹_爱你.gif",
                    "线条小狗第6弹_拍手.gif",
                    "线条小狗第7弹_爱你.gif"
                ]),
                .hydrationPrompt: bundled(f, .hydrationPrompt, ["线条小狗第11弹_吃手手.gif"]),
                .drinking: bundled(f, .drinking, ["线条小狗第20弹_喝咖啡.gif"]),
                .hydrationDone: bundled(f, .hydrationDone, [
                    "很棒.gif",
                    "线条小狗第8弹_扔心心.gif"
                ]),
                .focusGuard: bundled(f, .focusGuard, [
                    "线条小狗第18弹_工作.gif",
                    "线条小狗第6弹_写不动了.gif",
                    "线条小狗第9弹_写.gif"
                ]),
                .focusAlert: bundled(f, .focusAlert, [
                    "发现.gif",
                    "疑问.gif",
                    "线条小狗第20弹_警告.gif",
                    "线条小狗第6弹_惊讶.gif",
                    "线条小狗第8弹_哼.gif",
                    "线条小狗第9弹_疑问.gif"
                ]),
                .focusDone: bundled(f, .focusDone, [
                    "开心.gif",
                    "很棒.gif",
                    "线条小狗第14弹_庆祝.gif",
                    "线条小狗第6弹_拍手.gif"
                ]),
                .sad: bundled(f, .sad, [
                    "线条小狗第14弹_大哭.gif",
                    "线条小狗第6弹_呜呜.gif",
                    "线条小狗第7弹_对不起.gif",
                    "线条小狗第9弹_伤心.gif"
                ]),
                .sleeping: bundled(f, .sleeping, ["线条小狗第14弹_难受.gif"])
            ]
        )
    }
}
