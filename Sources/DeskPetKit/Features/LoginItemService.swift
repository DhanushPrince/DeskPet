import Foundation
import ServiceManagement

/// Launch-at-login via `SMAppService.mainApp`, replacing Electron's
/// `app.setLoginItemSettings`.
public enum LoginItemService {
    /// True when running from a real `.app` bundle. Unpackaged `swift test`
    /// binaries cannot register a login item, matching the Electron build's
    /// "development builds only save the preference" behaviour.
    public static var isPackaged: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func apply(enabled: Bool) {
        guard isPackaged else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("DeskPet: login item update failed: \(error)")
        }
    }

    /// Electron's `getLaunchAtLoginState`: the OS is source of truth when the
    /// binary is packaged; otherwise the stored preference is kept.
    public static func resolvedPreference(_ stored: Bool) -> Bool {
        guard isPackaged else { return stored }
        return isEnabled
    }
}
