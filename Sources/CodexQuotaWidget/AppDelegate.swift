import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let codexBundleIdentifier = "com.openai.codex"
    private let snapshotService = QuotaSnapshotService()
    private let stateStore = WidgetStateStore()
    private let touchBarController = TouchBarController()
    private let refreshQueue = DispatchQueue(label: "com.wendy.codex-quota-widget.refresh")
    private let loginItemController = LoginItemController()

    private lazy var windowController = WidgetWindowController(stateStore: stateStore)

    private var appObservers: [NSObjectProtocol] = []
    private var wakeObserver: NSObjectProtocol?
    private var refreshTimer: Timer?
    private var codexRunning = false
    private var fastRefreshUntil: Date?
    private var lastSnapshot: QuotaSnapshot?
    private var refreshInFlight = false
    private var language: WidgetLanguage = .english
    private var lastLoggedSource: String?
    private var lastRefreshTime: Date?
    /// 用户主动打开应用时置位：即使 Codex 未运行也保持浮窗可见，避免“打开没反应”。
    private var showsWithoutCodex = false

    private static let logFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex-quota-widget/widget.log")

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        widgetLog("applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)
        language = stateStore.load().language ?? .english
        touchBarController.setLanguage(language)
        windowController.onRequestRefresh = { [weak self] in
            self?.refreshState(reason: "manual-refresh", forceSnapshotReload: true)
        }
        windowController.onShowTouchBar = { [weak self] in
            self?.touchBarController.showAgain()
        }
        windowController.onOpenTouchBarSettings = { [weak self] in
            self?.openTouchBarSettings()
        }
        windowController.currentLanguage = { [weak self] in
            self?.language ?? .english
        }
        windowController.onSelectLanguage = { [weak self] language in
            self?.setLanguage(language)
        }
        windowController.supportsLoginItem = { [weak self] in
            self?.loginItemController.isSupported ?? false
        }
        windowController.loginItemEnabled = { [weak self] in
            self?.loginItemController.isEnabled ?? false
        }
        windowController.loginItemNeedsApproval = { [weak self] in
            self?.loginItemController.needsApproval ?? false
        }
        windowController.onToggleLoginItem = { [weak self] in
            self?.toggleLoginItem() ?? false
        }
        windowController.supportsTouchBar = {
            TouchBarCapability.isAvailable
        }
        windowController.lastRefreshText = { [weak self] in
            self?.lastRefreshTime.map(Self.clockFormatter.string(from:))
        }
        windowController.onOpenLog = { [weak self] in
            self?.openLog()
        }
        windowController.onShowAbout = { [weak self] in
            self?.showAbout()
        }
        // 未启用开机自启时，冷启动基本都是用户主动打开，直接显示占位浮窗而不是静默隐藏。
        showsWithoutCodex = !isCodexRunning() && !loginItemController.isEnabled
        startMonitoringCodex()
        startObservingWakeRequests()
        refreshState(reason: "launch")
    }

    /// 已在运行时再次从访达/Dock 打开应用，把浮窗重新显示出来。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let running = isCodexRunning()
        widgetLog("reopen request hasVisibleWindows=\(flag) codexRunning=\(running)")
        showsWithoutCodex = !running
        refreshState(reason: "reopen", forceSnapshotReload: true)
        windowController.show(snapshot: lastSnapshot)
        widgetLog("reopen showed capsule visible=\(windowController.window.isVisible)")
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        widgetLog("applicationWillTerminate")
        refreshTimer?.invalidate()
        touchBarController.codexDidExit()
        snapshotService.stop()
        let center = NSWorkspace.shared.notificationCenter
        appObservers.forEach(center.removeObserver(_:))
        if let wakeObserver {
            DistributedNotificationCenter.default().removeObserver(wakeObserver)
        }
    }

    /// 应用被再次打开时由第二个进程发出通知，这里负责把已隐藏的浮窗重新显示出来。
    private func startObservingWakeRequests() {
        wakeObserver = DistributedNotificationCenter.default.addObserver(
            forName: WidgetNotifications.showWidget,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let running = self.isCodexRunning()
            widgetLog("wake request received codexRunning=\(running)")
            self.showsWithoutCodex = !running
            self.refreshState(reason: "wake", forceSnapshotReload: true)
            self.windowController.show(snapshot: self.lastSnapshot)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func toggleLoginItem() -> Bool {
        let controller = loginItemController
        let enable = !controller.isEnabled

        if enable {
            if Bundle.main.bundleURL.path.hasPrefix("/Volumes/") {
                presentAlert(
                    title: language.text("Install the App First", "请先安装到应用程序"),
                    message: language.text(
                        "Launch at Login requires the app to live in /Applications. Drag it there from the disk image first.",
                        "开机自启需要应用位于 /Applications，请先把应用从磁盘映像拖入应用程序文件夹。"
                    )
                )
                return false
            }
            guard confirmLegacyAgentRemovalIfNeeded(controller) else {
                return controller.isEnabled
            }
        }

        do {
            try controller.setEnabled(enable)
        } catch {
            presentAlert(
                title: language.text("Could Not Update Launch at Login", "开机自启设置失败"),
                message: error.localizedDescription
            )
        }

        if enable, controller.needsApproval {
            presentAlert(
                title: language.text("Allow It in System Settings", "需要在系统设置中允许"),
                message: language.text(
                    "The login item was added. Allow Codex Quota Widget in System Settings > General > Login Items to start it at login.",
                    "已添加登录项，请在 系统设置 > 通用 > 登录项 中允许 Codex Quota Widget 开机启动。"
                )
            )
            openLoginItemsSettings()
        }
        return controller.isEnabled
    }

    /// 旧的 LaunchAgent 自启会和应用自启同时拉起两个进程，开启前先询问是否清掉。
    private func confirmLegacyAgentRemovalIfNeeded(_ controller: LoginItemController) -> Bool {
        guard controller.hasLegacyAgent else { return true }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = language.text(
            "Legacy Command-Line Startup Found",
            "检测到旧的命令行自启配置"
        )
        alert.informativeText = language.text(
            "~/Library/LaunchAgents/com.wendy.codex-quota-widget.plist starts the old build at login and conflicts with the app login item.\nMove it to the Trash before enabling?",
            "~/Library/LaunchAgents/com.wendy.codex-quota-widget.plist 会在登录时启动旧版本，并与应用自启冲突。\n是否将它移到废纸篓后再开启？"
        )
        alert.addButton(withTitle: language.text("Remove and Enable", "移除并开启"))
        alert.addButton(withTitle: language.text("Cancel", "取消"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }
        controller.removeLegacyAgent()
        return true
    }

    private func presentAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: language.text("OK", "好"))
        alert.runModal()
    }

    private func openLoginItemsSettings() {
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.users",
        ]

        for rawURL in settingsURLs {
            guard let url = URL(string: rawURL) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func startMonitoringCodex() {
        let center = NSWorkspace.shared.notificationCenter

        let launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleWorkspaceEvent(notification, launched: true)
        }

        let terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleWorkspaceEvent(notification, launched: false)
        }

        appObservers = [launchObserver, terminateObserver]
    }

    private func handleWorkspaceEvent(_ notification: Notification, launched: Bool) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            app.bundleIdentifier == codexBundleIdentifier
        else {
            return
        }

        if launched {
            fastRefreshUntil = Date().addingTimeInterval(120)
        }
        refreshState(reason: launched ? "codex-launch" : "codex-exit")
    }

    private func scheduleRefreshTimer(cadence: RefreshCadence) {
        if refreshTimer?.timeInterval == cadence.interval {
            return
        }

        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: cadence.interval, repeats: true) { [weak self] _ in
            self?.refreshState(reason: "refresh")
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    private func refreshState(reason: String, forceSnapshotReload: Bool = false) {
        let running = isCodexRunning()

        if running != codexRunning {
            codexRunning = running
            if running {
                fastRefreshUntil = Date().addingTimeInterval(120)
            }
        }

        if !running {
            touchBarController.codexDidExit()
            snapshotService.stop()
            lastSnapshot = nil
            lastLoggedSource = nil
            lastRefreshTime = nil
            if showsWithoutCodex {
                windowController.show(snapshot: nil)
            } else {
                windowController.hide()
            }
            scheduleRefreshTimer(cadence: .hidden)
            return
        }

        showsWithoutCodex = false

        if reason == "codex-launch" {
            touchBarController.codexDidLaunch()
        }

        windowController.show(snapshot: lastSnapshot)
        touchBarController.show(snapshot: lastSnapshot)
        refreshSnapshot(forceReload: forceSnapshotReload)
        scheduleRefreshTimer(cadence: currentCadence())

        if reason == "refresh", let fastRefreshUntil, fastRefreshUntil < Date() {
            scheduleRefreshTimer(cadence: .normal)
        }
    }

    private func currentCadence() -> RefreshCadence {
        if let fastRefreshUntil, fastRefreshUntil > Date() {
            return .fast
        }
        return .normal
    }

    private func isCodexRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: codexBundleIdentifier).isEmpty
    }

    private func setLanguage(_ newLanguage: WidgetLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        stateStore.update { state in
            state.language = newLanguage
        }
        touchBarController.setLanguage(newLanguage)
        touchBarController.showAgain()
        windowController.refreshLanguage()
    }

    private func openLog() {
        guard FileManager.default.fileExists(atPath: Self.logFileURL.path) else {
            presentAlert(
                title: language.text("Log Not Found", "日志文件不存在"),
                message: language.text(
                    "No log has been written yet at:\n\(Self.logFileURL.path)",
                    "尚未生成日志文件：\n\(Self.logFileURL.path)"
                )
            )
            return
        }
        NSWorkspace.shared.open(Self.logFileURL)
    }

    private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        var lines = [language.text("Version \(version)", "版本 \(version)")]
        if let build {
            lines.append(language.text("Build \(build)", "构建 \(build)"))
        }
        lines.append("macOS \(osVersion)")
        lines.append("")
        lines.append(language.text(
            "Unofficial personal tool, not affiliated with OpenAI.",
            "非官方个人工具，不代表 OpenAI。"
        ))
        presentAlert(title: "Codex Quota Widget", message: lines.joined(separator: "\n"))
    }

    private func openTouchBarSettings() {
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard",
        ]

        for rawURL in settingsURLs {
            guard let url = URL(string: rawURL) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func refreshSnapshot(forceReload: Bool) {
        if refreshInFlight {
            return
        }

        refreshInFlight = true
        refreshQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.snapshotService.latestSnapshot(forceReload: forceReload)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refreshInFlight = false
                guard self.codexRunning else {
                    return
                }

                self.lastSnapshot = snapshot
                self.lastRefreshTime = Date()
                let source = snapshot?.sourceFileName ?? "nil"
                if source != self.lastLoggedSource {
                    widgetLog("snapshot source=\(source)")
                    self.lastLoggedSource = source
                }
                self.windowController.show(snapshot: snapshot)
                self.touchBarController.show(snapshot: snapshot)
            }
        }
    }
}
