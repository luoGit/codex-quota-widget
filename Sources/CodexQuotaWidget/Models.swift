import Foundation

struct WindowQuota: Codable {
    let label: String
    let usedPercent: Double
    let remainingPercent: Double
    let resetsAt: Date?
}

struct QuotaSnapshot: Codable {
    let sourceFileName: String
    let eventTimestamp: Date?
    let detectedAt: Date
    let planType: String?
    let primary: WindowQuota
    let secondary: WindowQuota?
}

struct WidgetState: Codable {
    var originX: Double?
    var originY: Double?
    var language: WidgetLanguage?
}

enum WidgetLanguage: String, Codable {
    case english
    case chinese

    var isChinese: Bool {
        self == .chinese
    }

    /// 显示在语言子菜单里的选项名，两种界面语言下都保持自身写法。
    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .chinese:
            return "中文"
        }
    }

    func text(_ english: String, _ chinese: String) -> String {
        isChinese ? chinese : english
    }
}

enum RefreshCadence {
    case hidden
    case fast
    case normal

    var interval: TimeInterval {
        switch self {
        case .hidden:
            return 5
        case .fast:
            return 1
        case .normal:
            return 2
        }
    }
}

enum WidgetNotifications {
    /// 第二个实例启动时广播，让已运行的实例把浮窗唤到前面。
    static let showWidget = Notification.Name("com.wendy.codex-quota-widget.show-widget")
}
