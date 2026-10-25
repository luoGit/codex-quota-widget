import AppKit

final class WidgetWindowController: NSObject, NSWindowDelegate {
    let window: NSPanel
    var onRequestRefresh: (() -> Void)?
    var onShowTouchBar: (() -> Void)?
    var onOpenTouchBarSettings: (() -> Void)?
    var currentLanguage: (() -> WidgetLanguage)?
    var onSelectLanguage: ((WidgetLanguage) -> Void)?
    var supportsLoginItem: (() -> Bool)?
    var loginItemEnabled: (() -> Bool)?
    var loginItemNeedsApproval: (() -> Bool)?
    var onToggleLoginItem: (() -> Bool)?
    var supportsTouchBar: (() -> Bool)?
    var lastRefreshText: (() -> String?)?
    var onOpenLog: (() -> Void)?
    var onShowAbout: (() -> Void)?

    private let stateStore: WidgetStateStore
    private let contentView = WidgetContentView()
    private var isExpanded = false
    private var hasPlacedWindow = false

    init(stateStore: WidgetStateStore) {
        self.stateStore = stateStore
        self.window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 154, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()

        setupWindow()
        setupContent()
        restoreInitialPlacement()
    }

    func show(snapshot: QuotaSnapshot?) {
        update(snapshot: snapshot)
        if !hasPlacedWindow {
            restoreInitialPlacement()
        }
        if !window.isVisible {
            window.orderFrontRegardless()
        }
    }

    func hide() {
        window.orderOut(nil)
    }

    func toggleExpanded() {
        isExpanded.toggle()
        applySize(animated: true)
    }

    func update(snapshot: QuotaSnapshot?) {
        contentView.render(snapshot: snapshot)
        syncWindowSize(animated: false)
    }

    /// 语言切换后按当前快照重绘文案，并重新计算可能变化的宽度。
    func refreshLanguage() {
        contentView.refreshLanguage()
        syncWindowSize(animated: false)
    }

    func windowDidMove(_ notification: Notification) {
        let frame = window.frame
        stateStore.save(WidgetState(originX: frame.origin.x, originY: frame.origin.y))
    }

    private func setupWindow() {
        window.delegate = self
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func setupContent() {
        contentView.onToggleExpanded = { [weak self] in
            self?.toggleExpanded()
        }
        contentView.onRequestRefresh = { [weak self] in
            self?.onRequestRefresh?()
        }
        contentView.onShowTouchBar = { [weak self] in
            self?.onShowTouchBar?()
        }
        contentView.onOpenTouchBarSettings = { [weak self] in
            self?.onOpenTouchBarSettings?()
        }
        contentView.currentLanguage = { [weak self] in
            self?.currentLanguage?() ?? .english
        }
        contentView.onSelectLanguage = { [weak self] language in
            self?.onSelectLanguage?(language)
        }
        contentView.supportsLoginItem = { [weak self] in
            self?.supportsLoginItem?() ?? false
        }
        contentView.loginItemEnabled = { [weak self] in
            self?.loginItemEnabled?() ?? false
        }
        contentView.loginItemNeedsApproval = { [weak self] in
            self?.loginItemNeedsApproval?() ?? false
        }
        contentView.onToggleLoginItem = { [weak self] in
            self?.onToggleLoginItem?() ?? false
        }
        contentView.supportsTouchBar = { [weak self] in
            self?.supportsTouchBar?() ?? false
        }
        contentView.lastRefreshText = { [weak self] in
            self?.lastRefreshText?()
        }
        contentView.onOpenLog = { [weak self] in
            self?.onOpenLog?()
        }
        contentView.onShowAbout = { [weak self] in
            self?.onShowAbout?()
        }
        window.contentView = contentView

        applySize(animated: false)
    }

    private func restoreInitialPlacement() {
        let state = stateStore.load()
        if let x = state.originX, let y = state.originY {
            window.setFrameOrigin(clampedOrigin(for: NSPoint(x: x, y: y), size: currentSize))
        } else {
            let frame = defaultFrame(for: currentSize)
            window.setFrame(frame, display: false)
        }
        hasPlacedWindow = true
    }

    private var currentSize: NSSize {
        contentView.preferredSize(expanded: isExpanded)
    }

    private func syncWindowSize(animated: Bool) {
        let target = currentSize
        let frame = window.frame
        guard abs(target.width - frame.width) > 0.5 || abs(target.height - frame.height) > 0.5 else {
            return
        }
        applySize(animated: animated)
    }

    private func applySize(animated: Bool = true) {
        contentView.setExpanded(isExpanded)
        let newSize = currentSize
        var frame = window.frame
        let deltaHeight = newSize.height - frame.size.height
        frame.origin.y -= deltaHeight
        frame.size = newSize
        frame.origin = clampedOrigin(for: frame.origin, size: frame.size)
        window.setFrame(frame, display: true, animate: animated)
    }

    private func defaultFrame(for size: NSSize) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        let x = visible.maxX - size.width - 18
        let y = visible.maxY - size.height - 26
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func clampedOrigin(for origin: NSPoint, size: NSSize) -> NSPoint {
        let screen = screenContaining(point: origin) ?? NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame

        let minX = visible.minX + 8
        let maxX = visible.maxX - size.width - 8
        let minY = visible.minY + 8
        let maxY = visible.maxY - size.height - 8

        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    private func screenContaining(point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}

private enum WidgetLayout {
    static let minCollapsedWidth: CGFloat = 92
    static let maxExpandedContentWidth: CGFloat = 260
    static let collapsedHeight: CGFloat = 32
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 6
    static let sectionSpacing: CGFloat = 7
}

private final class WidgetContentView: NSView {
    var onToggleExpanded: (() -> Void)?
    var onRequestRefresh: (() -> Void)?
    var onShowTouchBar: (() -> Void)?
    var onOpenTouchBarSettings: (() -> Void)?
    var onSelectLanguage: ((WidgetLanguage) -> Void)?
    var currentLanguage: (() -> WidgetLanguage)?
    var supportsLoginItem: (() -> Bool)?
    var loginItemEnabled: (() -> Bool)?
    var loginItemNeedsApproval: (() -> Bool)?
    var onToggleLoginItem: (() -> Bool)?
    var supportsTouchBar: (() -> Bool)?
    var lastRefreshText: (() -> String?)?
    var onOpenLog: (() -> Void)?
    var onShowAbout: (() -> Void)?
    private var mouseDownWindowOrigin: NSPoint?
    private var suppressNextMouseUp = false
    private var lastSnapshot: QuotaSnapshot?

    private let summaryStack = NSStackView()
    private let primarySummaryView = SummaryQuotaView(title: "5h")
    private let secondarySummaryView = SummaryQuotaView(title: "7d")
    private let detailStack = NSStackView()
    private let fiveHourLabel = NSTextField(labelWithString: "5h: --")
    private let sevenDayLabel = NSTextField(labelWithString: "7d: --")
    private let resetLabel = NSTextField(labelWithString: "重置: --")
    private let freshnessLabel = NSTextField(labelWithString: "最新日志: --")
    private let planLabel = NSTextField(labelWithString: "套餐: --")
    private let container = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    func render(snapshot: QuotaSnapshot?) {
        lastSnapshot = snapshot
        layer?.backgroundColor = WidgetColors.backgroundColor.cgColor

        let language = currentLanguage?() ?? .english
        let sourceLabel = language.text("Source", "数据来源")
        let planLabelTitle = language.text("Plan", "套餐")
        let resetTitle = language.text("Reset", "重置")
        let notProvided = language.text("not provided by current log", "当前日志未提供")
        let waiting = language.text("waiting for Codex quota data", "等 Codex 写入额度数据")

        if let snapshot {
            let windows = normalizedWindows(from: snapshot)
            let fiveHour = windows.fiveHour
            let sevenDay = windows.sevenDay
            primarySummaryView.isHidden = fiveHour == nil
            secondarySummaryView.isHidden = sevenDay == nil

            primarySummaryView.render(
                label: "5h",
                remainingPercent: fiveHour.map { Int($0.remainingPercent.rounded()) },
                color: WidgetColors.color(for: fiveHour?.remainingPercent)
            )
            primarySummaryView.toolTip = fiveHour.map {
                language.text(
                    "5h: \(Int($0.remainingPercent.rounded()))% remaining",
                    "5h: 剩余 \(Int($0.remainingPercent.rounded()))%"
                )
            } ?? "5h: \(notProvided)"

            secondarySummaryView.render(
                label: "7d",
                remainingPercent: sevenDay.map { Int($0.remainingPercent.rounded()) },
                color: WidgetColors.color(for: sevenDay?.remainingPercent)
            )
            secondarySummaryView.toolTip = sevenDay.map {
                language.text(
                    "7d: \(Int($0.remainingPercent.rounded()))% remaining",
                    "7d: 剩余 \(Int($0.remainingPercent.rounded()))%"
                )
            } ?? "7d: \(notProvided)"

            if let fiveHour {
                fiveHourLabel.stringValue = language.text(
                    "5h: \(Int(fiveHour.remainingPercent.rounded()))% left · \(Int(fiveHour.usedPercent.rounded()))% used",
                    "5h: 剩余 \(Int(fiveHour.remainingPercent.rounded()))% · 已用 \(Int(fiveHour.usedPercent.rounded()))%"
                )
            } else {
                fiveHourLabel.stringValue = "5h: \(notProvided)"
            }
            fiveHourLabel.isHidden = fiveHour == nil

            if let sevenDay {
                sevenDayLabel.stringValue = language.text(
                    "7d: \(Int(sevenDay.remainingPercent.rounded()))% left · \(Int(sevenDay.usedPercent.rounded()))% used",
                    "7d: 剩余 \(Int(sevenDay.remainingPercent.rounded()))% · 已用 \(Int(sevenDay.usedPercent.rounded()))%"
                )
            } else {
                sevenDayLabel.stringValue = "7d: \(notProvided)"
            }
            sevenDayLabel.isHidden = sevenDay == nil

            let resetParts = [
                fiveHour.map { "5h \(WidgetFormatter.timeUntilReset($0.resetsAt, language: language))" },
                sevenDay.map { "7d \(WidgetFormatter.timeUntilReset($0.resetsAt, language: language))" },
            ].compactMap { $0 }
            resetLabel.stringValue = "\(resetTitle): \(resetParts.isEmpty ? "--" : resetParts.joined(separator: " · "))"

            let age = WidgetFormatter.relativeAge(snapshot.eventTimestamp, language: language)
            let compactSource = WidgetFormatter.compactSourceName(snapshot.sourceFileName, language: language)
            freshnessLabel.stringValue = "\(sourceLabel): \(compactSource) · \(age)"
            freshnessLabel.toolTip = "\(sourceLabel): \(snapshot.sourceFileName) · \(age)"
            planLabel.stringValue = "\(planLabelTitle): \(snapshot.planType ?? language.text("unknown", "未知"))"
        } else {
            primarySummaryView.isHidden = false
            secondarySummaryView.isHidden = false
            primarySummaryView.render(label: "5h", remainingPercent: nil, color: WidgetColors.mutedColor)
            secondarySummaryView.render(label: "7d", remainingPercent: nil, color: WidgetColors.mutedColor)
            primarySummaryView.toolTip = "5h: \(waiting)"
            secondarySummaryView.toolTip = "7d: \(waiting)"
            fiveHourLabel.isHidden = true
            sevenDayLabel.isHidden = false
            fiveHourLabel.stringValue = "5h: \(waiting)"
            sevenDayLabel.stringValue = "7d: \(waiting)"
            resetLabel.stringValue = "\(resetTitle): --"
            freshnessLabel.stringValue = "\(sourceLabel): \(language.text("none", "暂无"))"
            freshnessLabel.toolTip = nil
            planLabel.stringValue = "\(planLabelTitle): --"
        }
    }

    /// 语言切换后按最后一次快照重绘，避免等下一次刷新才更新文案。
    func refreshLanguage() {
        render(snapshot: lastSnapshot)
    }

    func setExpanded(_ expanded: Bool) {
        detailStack.isHidden = !expanded
    }

    /// 按当前可见内容测量胶囊尺寸：收起态只算额度摘要，展开态取摘要与详情中的较宽者并限制最大宽度。
    func preferredSize(expanded: Bool) -> NSSize {
        let lanes = [primarySummaryView, secondarySummaryView].filter { !$0.isHidden }
        let laneWidth = lanes.map(\.intrinsicContentSize.width).max() ?? 0
        let laneHeight = lanes.map(\.intrinsicContentSize.height).max() ?? 0
        let summaryWidth = lanes.isEmpty
            ? 0
            : laneWidth * CGFloat(lanes.count) + summaryStack.spacing * CGFloat(lanes.count - 1)
        let collapsedWidth = max(WidgetLayout.minCollapsedWidth, ceil(summaryWidth) + WidgetLayout.horizontalPadding * 2)
        guard expanded else {
            return NSSize(width: collapsedWidth, height: WidgetLayout.collapsedHeight)
        }

        let rows = [fiveHourLabel, sevenDayLabel, resetLabel, freshnessLabel, planLabel].filter { !$0.isHidden }
        let detailWidth = rows.map { $0.fittingSize.width }.max() ?? 0
        let detailHeight = rows.reduce(0) { $0 + $1.fittingSize.height }
            + detailStack.spacing * CGFloat(max(0, rows.count - 1))
        let contentWidth = min(max(summaryWidth, detailWidth), WidgetLayout.maxExpandedContentWidth)
        let contentHeight = laneHeight + WidgetLayout.sectionSpacing + detailHeight
        return NSSize(
            width: max(collapsedWidth, ceil(contentWidth) + WidgetLayout.horizontalPadding * 2),
            height: ceil(contentHeight) + WidgetLayout.verticalPadding * 2
        )
    }

    private func setupViews() {
        container.orientation = .vertical
        container.alignment = .centerX
        container.spacing = WidgetLayout.sectionSpacing
        container.translatesAutoresizingMaskIntoConstraints = false

        summaryStack.orientation = .horizontal
        summaryStack.alignment = .centerY
        summaryStack.distribution = .fillEqually
        summaryStack.spacing = 8
        summaryStack.translatesAutoresizingMaskIntoConstraints = false
        summaryStack.addArrangedSubview(primarySummaryView)
        summaryStack.addArrangedSubview(secondarySummaryView)
        primarySummaryView.translatesAutoresizingMaskIntoConstraints = false
        secondarySummaryView.translatesAutoresizingMaskIntoConstraints = false

        [fiveHourLabel, sevenDayLabel, resetLabel, freshnessLabel, planLabel].forEach { label in
            label.font = .systemFont(ofSize: 11, weight: .regular)
            label.textColor = NSColor.white.withAlphaComponent(0.9)
            label.lineBreakMode = .byTruncatingTail
            detailStack.addArrangedSubview(label)
        }
        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 4
        detailStack.isHidden = true

        container.addArrangedSubview(summaryStack)
        container.addArrangedSubview(detailStack)
        addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: WidgetLayout.horizontalPadding),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -WidgetLayout.horizontalPadding),
            container.centerYAnchor.constraint(equalTo: centerYAnchor),
            container.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: WidgetLayout.verticalPadding),
            container.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -WidgetLayout.verticalPadding),
        ])
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            suppressNextMouseUp = true
            showContextMenu(with: event)
            return
        }

        mouseDownWindowOrigin = window?.frame.origin
    }

    override func mouseUp(with event: NSEvent) {
        if suppressNextMouseUp {
            suppressNextMouseUp = false
            return
        }

        guard isClickWithoutDrag() else {
            return
        }

        if event.clickCount >= 2 {
            onRequestRefresh?()
            return
        }

        onToggleExpanded?()
    }

    override func rightMouseDown(with event: NSEvent) {
        showContextMenu(with: event)
    }

    private func isClickWithoutDrag() -> Bool {
        guard
            let downOrigin = mouseDownWindowOrigin,
            let currentOrigin = window?.frame.origin
        else {
            return true
        }
        return abs(currentOrigin.x - downOrigin.x) < 1 && abs(currentOrigin.y - downOrigin.y) < 1
    }

    private func showContextMenu(with event: NSEvent) {
        let menu = NSMenu()
        let language = currentLanguage?() ?? .english
        let expanded = !detailStack.isHidden

        let toggleItem = NSMenuItem(
            title: expanded
                ? language.text("Collapse Details", "收起详情")
                : language.text("Expand Details", "展开详情"),
            action: #selector(handleContextToggle),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        var refreshTitle = language.text("Refresh Now", "立即刷新")
        if let lastRefresh = lastRefreshText?() {
            refreshTitle += language.text(" (last \(lastRefresh))", "（上次 \(lastRefresh)）")
        }
        let refreshItem = NSMenuItem(
            title: refreshTitle,
            action: #selector(handleContextRefresh),
            keyEquivalent: ""
        )
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        if supportsTouchBar?() ?? false {
            let touchBarItem = NSMenuItem(
                title: language.text("Show in Touch Bar", "显示 Touch Bar"),
                action: #selector(handleContextShowTouchBar),
                keyEquivalent: ""
            )
            touchBarItem.target = self
            menu.addItem(touchBarItem)

            let touchBarSettingsItem = NSMenuItem(
                title: language.text("Open Touch Bar Settings…", "打开 Touch Bar 设置…"),
                action: #selector(handleContextOpenTouchBarSettings),
                keyEquivalent: ""
            )
            touchBarSettingsItem.target = self
            menu.addItem(touchBarSettingsItem)
            menu.addItem(.separator())
        }

        let languageItem = NSMenuItem(title: language.text("Language", "界面语言"), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        for option in [WidgetLanguage.english, .chinese] {
            let optionItem = NSMenuItem(
                title: option.displayName,
                action: #selector(handleContextSelectLanguage(_:)),
                keyEquivalent: ""
            )
            optionItem.target = self
            optionItem.representedObject = option.rawValue
            optionItem.state = option == language ? .on : .off
            languageMenu.addItem(optionItem)
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)
        menu.addItem(.separator())

        if supportsLoginItem?() ?? false {
            let needsApproval = loginItemNeedsApproval?() ?? false
            let loginItem = NSMenuItem(
                title: needsApproval
                    ? language.text("Launch at Login (Allow in System Settings)", "开机自启（需在系统设置允许）")
                    : language.text("Launch at Login", "开机自启"),
                action: #selector(handleContextToggleLoginItem),
                keyEquivalent: ""
            )
            loginItem.target = self
            loginItem.state = (loginItemEnabled?() ?? false) ? .on : .off
            menu.addItem(loginItem)
        }

        let openLogItem = NSMenuItem(
            title: language.text("Open Log", "打开日志"),
            action: #selector(handleContextOpenLog),
            keyEquivalent: ""
        )
        openLogItem.target = self
        menu.addItem(openLogItem)

        let aboutItem = NSMenuItem(
            title: language.text("About Codex Quota Widget", "关于 Codex Quota Widget"),
            action: #selector(handleContextShowAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: language.text("Quit Codex Quota Widget", "退出 Codex Quota Widget"),
            action: #selector(handleContextQuit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc
    private func handleContextToggle() {
        onToggleExpanded?()
    }

    @objc
    private func handleContextRefresh() {
        onRequestRefresh?()
    }

    @objc
    private func handleContextShowTouchBar() {
        onShowTouchBar?()
    }

    @objc
    private func handleContextOpenTouchBarSettings() {
        onOpenTouchBarSettings?()
    }

    @objc
    private func handleContextSelectLanguage(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let language = WidgetLanguage(rawValue: rawValue)
        else {
            return
        }
        onSelectLanguage?(language)
    }

    @objc
    private func handleContextToggleLoginItem() {
        _ = onToggleLoginItem?()
    }

    @objc
    private func handleContextOpenLog() {
        onOpenLog?()
    }

    @objc
    private func handleContextShowAbout() {
        onShowAbout?()
    }

    @objc
    private func handleContextQuit() {
        NSApp.terminate(nil)
    }

    private func normalizedWindows(from snapshot: QuotaSnapshot) -> (fiveHour: WindowQuota?, sevenDay: WindowQuota?) {
        let windows = [snapshot.primary, snapshot.secondary].compactMap { $0 }
        let fiveHour = windows.first { $0.label == "5h" }
        let sevenDay = windows.first { $0.label == "7d" }
        return (fiveHour, sevenDay)
    }
}

enum WidgetColors {
    static let backgroundColor = NSColor(calibratedRed: 0.07, green: 0.1, blue: 0.15, alpha: 0.94)
    static let mutedColor = NSColor.white.withAlphaComponent(0.45)

    static func color(for remainingPercent: Double?) -> NSColor {
        let value = remainingPercent ?? 0
        switch value {
        case 60...:
            return NSColor(calibratedRed: 0.23, green: 0.79, blue: 0.39, alpha: 1)
        case 30...:
            return NSColor(calibratedRed: 0.97, green: 0.72, blue: 0.22, alpha: 1)
        default:
            return NSColor(calibratedRed: 0.96, green: 0.4, blue: 0.36, alpha: 1)
        }
    }
}

private final class SummaryQuotaView: NSView {
    private let colorDot = DotView()
    private let valueLabel = NSTextField(labelWithString: "--")
    private let contentStack = NSStackView()

    override var intrinsicContentSize: NSSize {
        contentStack.fittingSize
    }

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = false
        setupViews()
        render(label: title, remainingPercent: nil, color: WidgetColors.mutedColor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(label: String, remainingPercent: Int?, color: NSColor) {
        colorDot.fillColor = color
        let percentText: String
        if let remainingPercent {
            percentText = String(format: "%3d%%", remainingPercent)
        } else {
            percentText = " --%"
        }
        valueLabel.stringValue = "\(label) \(percentText)"
        invalidateIntrinsicContentSize()
    }

    private func setupViews() {
        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 5
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        valueLabel.textColor = .white
        valueLabel.alignment = .center
        valueLabel.lineBreakMode = .byClipping
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        contentStack.addArrangedSubview(colorDot)
        contentStack.addArrangedSubview(valueLabel)
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            colorDot.widthAnchor.constraint(equalToConstant: 6),
            colorDot.heightAnchor.constraint(equalToConstant: 6),
            contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }
}

private final class DotView: NSView {
    var fillColor: NSColor = .white {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        fillColor.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

private enum WidgetFormatter {
    static func timeUntilReset(_ date: Date?, language: WidgetLanguage) -> String {
        guard let date else { return "--" }
        let delta = Int(date.timeIntervalSinceNow)
        guard delta > 0 else { return language.text("reset", "已重置") }

        let hours = delta / 3600
        let minutes = (delta % 3600) / 60

        if hours >= 24 {
            return "\(hours / 24)d \(hours % 24)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    static func relativeAge(_ date: Date?, language: WidgetLanguage) -> String {
        guard let date else { return language.text("unknown", "未知") }
        let delta = max(0, Int(-date.timeIntervalSinceNow))
        if delta < 60 {
            return language.text("\(delta)s ago", "\(delta)s 前")
        }
        let minutes = delta / 60
        if minutes < 60 {
            return language.text("\(minutes)m ago", "\(minutes)m 前")
        }
        let hours = minutes / 60
        if hours < 24 {
            return language.text("\(hours)h ago", "\(hours)h 前")
        }
        return language.text("\(hours / 24)d ago", "\(hours / 24)d 前")
    }

    /// 日志文件名形如 rollout-2026-10-21T19-40-18-<uuid>.jsonl，压缩成 "日志 10-21 19:40" 避免详情行被截断。
    static func compactSourceName(_ name: String, language: WidgetLanguage) -> String {
        guard name.hasSuffix(".jsonl") else { return name }
        let parts = name.split(separator: "-")
        guard parts.count >= 6, parts[0] == "rollout" else { return name }
        guard let separatorIndex = parts[3].firstIndex(of: "T") else { return name }
        let date = "\(parts[2])-\(parts[3][..<separatorIndex])"
        let hour = parts[3][parts[3].index(after: separatorIndex)...]
        return language.text("Log \(date) \(hour):\(parts[4])", "日志 \(date) \(hour):\(parts[4])")
    }
}
