import Foundation
import ServiceManagement

/// 应用版开机自启：优先使用系统登录项，并负责清理遗留的 LaunchAgent 配置。
final class LoginItemController {
    private static let legacyAgentLabel = "com.wendy.codex-quota-widget"

    var isSupported: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    var needsApproval: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .requiresApproval
    }

    var hasLegacyAgent: Bool {
        FileManager.default.fileExists(atPath: Self.legacyAgentURL.path)
    }

    func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func removeLegacyAgent() {
        try? FileManager.default.trashItem(at: Self.legacyAgentURL, resultingItemURL: nil)
    }

    private static var legacyAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(legacyAgentLabel).plist")
    }
}
