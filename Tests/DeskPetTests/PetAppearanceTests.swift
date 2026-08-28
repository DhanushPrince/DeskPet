import Foundation
import Testing
@testable import DeskPetKit

/// Ported from `tests/petAppearances.test.ts`, extended to cover all three
/// appearances rather than only Xiao Ji Mao.
@Suite("Pet appearances")
struct PetAppearanceTests {

    // MARK: Ported cases

    @Test("options() includes Xiao Ji Mao")
    func optionsIncludeXiaoJiMao() {
        #expect(PetAppearances.options().contains { $0.value == .xiaoJiMao })
    }

    @Test("persisted appearance id round-trips xiaoJiMao")
    func resolveAppearanceID() {
        #expect(PetAppearanceID(persisted: "xiaoJiMao") == .xiaoJiMao)
    }

    @Test("unknown or missing appearance ids collapse to lineDog")
    func resolveAppearanceIDFallback() {
        #expect(PetAppearanceID(persisted: "nonsense") == .lineDog)
        #expect(PetAppearanceID(persisted: nil) == .lineDog)
        // `custom` is a valid selection, but has no built-in manifest.
        #expect(PetAppearanceID(persisted: "custom") == .custom)
        #expect(PetAppearanceID.custom.builtIn == .lineDog)
    }

    @Test("custom assets require idle and fall back to idle for missing states")
    func customAssetFallback() throws {
        let custom = CustomPetAppearance(
            name: "Custom",
            assets: [
                .idle: CustomPetAsset(
                    relativePath: "custom_pet_assets/idle/idle.gif",
                    originalName: "idle.gif",
                    updatedAt: 1
                )
            ]
        )

        #expect(PetAppearances.hasRequiredAssets(custom))

        let resolved = try #require(PetAppearances.customAssetDefinition(custom, .focusAlert))
        #expect(resolved.paths == ["custom_pet_assets/idle/idle.gif"])
        #expect(resolved.isPlaceholder)
        #expect(resolved.source == .custom)
    }

    @Test("a custom appearance without idle is unusable")
    func customAssetsWithoutIdle() {
        let custom = CustomPetAppearance(
            name: "Custom",
            assets: [
                .happy: CustomPetAsset(
                    relativePath: "custom_pet_assets/happy/happy.gif",
                    originalName: "happy.gif",
                    updatedAt: 1
                )
            ]
        )
        #expect(!PetAppearances.hasRequiredAssets(custom))
        #expect(PetAppearances.customAssetDefinition(custom, .happy) == nil)
        #expect(!PetAppearances.hasRequiredAssets(nil))
    }

    @Test("a state with its own custom asset is not a placeholder")
    func customAssetExactMatch() throws {
        let custom = CustomPetAppearance(
            name: "Custom",
            assets: [
                .idle: CustomPetAsset(
                    relativePath: "custom_pet_assets/idle/idle.gif",
                    originalName: "idle.gif",
                    updatedAt: 1
                ),
                .happy: CustomPetAsset(
                    relativePath: "custom_pet_assets/happy/happy.gif",
                    originalName: "happy.gif",
                    updatedAt: 1
                )
            ]
        )
        let resolved = try #require(PetAppearances.customAssetDefinition(custom, .happy))
        #expect(resolved.paths == ["custom_pet_assets/happy/happy.gif"])
        #expect(!resolved.isPlaceholder)
    }

    // MARK: Resolution chain

    @Test("every appearance resolves a definition for every state", arguments: BuiltInPetAppearanceID.allCases)
    func everyStateResolves(appearance: BuiltInPetAppearanceID) {
        let id = PetAppearanceID(rawValue: appearance.rawValue)!
        for state in PetState.allCases {
            let definition = PetAppearances.assetDefinition(appearance: id, state: state)
            #expect(!definition.paths.isEmpty, "\(appearance.rawValue)/\(state.rawValue) has no paths")
        }
    }

    @Test("Golden Puppy borrows happy artwork for the three *Done states")
    func goldenPuppyDoneStatesBorrowHappy() {
        let happy = PetAppearances.assetDefinition(appearance: .lovartPuppy, state: .happy)
        for state in [PetState.breakDone, .hydrationDone, .focusDone] {
            let resolved = PetAppearances.assetDefinition(appearance: .lovartPuppy, state: state)
            #expect(resolved.paths == happy.paths, "\(state.rawValue) should borrow happy")
        }
    }

    @Test("Line Dog has its own artwork for the three *Done states")
    func lineDogDoneStatesAreDistinct() {
        let happy = PetAppearances.assetDefinition(appearance: .lineDog, state: .happy)
        for state in [PetState.breakDone, .hydrationDone, .focusDone] {
            let resolved = PetAppearances.assetDefinition(appearance: .lineDog, state: state)
            #expect(resolved.paths != happy.paths, "\(state.rawValue) should not borrow happy")
        }
    }

    @Test("placeholder states are flagged")
    func placeholderFlags() {
        // Line Dog's `sitting` borrows an idle GIF and is marked a placeholder.
        #expect(PetAppearances.assetDefinition(appearance: .lineDog, state: .sitting).isPlaceholder)
        #expect(!PetAppearances.assetDefinition(appearance: .lineDog, state: .idle).isPlaceholder)
        // Golden Puppy reuses its sleeping GIF for `sad`.
        #expect(PetAppearances.assetDefinition(appearance: .lovartPuppy, state: .sad).isPlaceholder)
    }

    @Test("Golden Puppy breakRunning carries the 4500ms replay interval")
    func replayInterval() {
        let running = PetAppearances.assetDefinition(appearance: .lovartPuppy, state: .breakRunning)
        #expect(running.replayIntervalMs == 4500)
        // No other appearance sets one.
        #expect(PetAppearances.assetDefinition(appearance: .lineDog, state: .breakRunning).replayIntervalMs == nil)
    }

    @Test("displayOrder covers every built-in appearance")
    func displayOrderCoversAllAppearances() {
        #expect(Set(PetAppearances.displayOrder) == Set(BuiltInPetAppearanceID.allCases))
        #expect(PetAppearances.all.count == BuiltInPetAppearanceID.allCases.count)
    }

    @Test("PetState.allCases matches PET_STATE_ORDER from the Electron source")
    func stateOrderMatchesSource() {
        #expect(PetState.allCases.map(\.rawValue) == [
            "idle", "sitting", "happy", "breakPrompt", "breakRunning", "breakDone",
            "hydrationPrompt", "drinking", "hydrationDone", "focusGuard", "focusAlert",
            "focusDone", "sad", "sleeping"
        ])
    }

    // MARK: Bundle existence — catches asset rename mistakes mechanically

    @Test("the bundled PetAssets directory is reachable")
    func bundledRootExists() throws {
        _ = try #require(PetAssetLoader.bundledRoot, "PetAssets missing from the resource bundle")
    }

    @Test(
        "every resolved variant exists on disk for every state",
        arguments: BuiltInPetAppearanceID.allCases
    )
    func everyVariantExists(appearance: BuiltInPetAppearanceID) throws {
        let root = try #require(PetAssetLoader.bundledRoot)
        let id = PetAppearanceID(rawValue: appearance.rawValue)!

        for state in PetState.allCases {
            let definition = PetAppearances.assetDefinition(appearance: id, state: state)
            #expect(definition.source == .bundled)
            for path in definition.paths {
                let url = root.appendingPathComponent(path)
                #expect(
                    PetAssetLoader.exists(url),
                    "missing asset for \(appearance.rawValue)/\(state.rawValue): \(path)"
                )
            }
        }
    }

    @Test("every declared manifest variant exists, including unreferenced states")
    func everyManifestVariantExists() throws {
        let root = try #require(PetAssetLoader.bundledRoot)
        for id in BuiltInPetAppearanceID.allCases {
            let manifest = PetAppearances.manifest(id)
            var definitions = Array(manifest.states.values)
            definitions.append(manifest.fallback)
            for definition in definitions {
                for path in definition.paths {
                    #expect(
                        PetAssetLoader.exists(root.appendingPathComponent(path)),
                        "missing declared asset: \(path)"
                    )
                }
            }
        }
    }
}
