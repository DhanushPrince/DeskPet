import Foundation

/// Copies a user-picked GIF into `custom_pet_assets/` under Application Support.
///
/// Ported from `importCustomPetAsset` in the Electron main process.
public enum CustomAssetImporter {
    /// `originalName.replace(/[^a-zA-Z0-9._-]+/g, "-")`.
    public static func sanitizeFileName(_ originalName: String) -> String {
        let pattern = try? NSRegularExpression(pattern: "[^a-zA-Z0-9._-]+")
        let range = NSRange(originalName.startIndex..<originalName.endIndex, in: originalName)
        let replaced = pattern?.stringByReplacingMatches(
            in: originalName, range: range, withTemplate: "-"
        ) ?? originalName
        return replaced.isEmpty ? "pet.gif" : replaced
    }

    /// Copies `source` into `supportDirectory/custom_pet_assets/<state>/`.
    /// Returns nil for a non-GIF or if the copy cannot be contained in the root.
    public static func importGIF(
        state: PetState,
        from source: URL,
        into supportDirectory: URL,
        now: Date
    ) -> CustomPetAsset? {
        guard source.pathExtension.lowercased() == "gif" else { return nil }

        let originalName = source.lastPathComponent
        let safeName = sanitizeFileName(originalName)
        let timestamp = Int((now.timeIntervalSince1970 * 1000).rounded())
        let fileName = "\(state.rawValue)-\(timestamp)-\(safeName)"
        let relativePath = "custom_pet_assets/\(state.rawValue)/\(fileName)"
        guard Settings.isValidCustomAssetPath(relativePath) else { return nil }

        let stateDir = supportDirectory
            .appendingPathComponent("custom_pet_assets", isDirectory: true)
            .appendingPathComponent(state.rawValue, isDirectory: true)
        let destination = stateDir.appendingPathComponent(fileName)

        guard PetAssetLoader.isInsideCustomRoot(
            destination, supportDirectory: supportDirectory
        ) else { return nil }

        do {
            try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            NSLog("DeskPet: custom asset copy failed: \(error)")
            return nil
        }

        return CustomPetAsset(
            relativePath: relativePath,
            originalName: originalName,
            updatedAt: now.timeIntervalSince1970 * 1000
        )
    }
}
