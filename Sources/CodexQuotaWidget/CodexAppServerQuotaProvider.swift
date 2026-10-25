import Foundation

final class CodexAppServerQuotaProvider {
    private final class PendingResponse {
        let semaphore = DispatchSemaphore(value: 0)
        var message: [String: Any]?
    }

    private let codexURL: URL
    private let queue = DispatchQueue(label: "com.wendy.codex-quota-widget.app-server")
    private let lock = NSLock()

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputBuffer = ""
    private var errorBuffer = ""
    private var pendingResponses: [Int: PendingResponse] = [:]
    private var nextRequestID = 1
    private var initialized = false
    private var retryAfter = Date.distantPast

    init(codexURL: URL? = nil) {
        self.codexURL = codexURL ?? Self.discoverCodexURL()
    }

    func latestSnapshot(timeout: TimeInterval = 3) -> QuotaSnapshot? {
        queue.sync {
            guard Date() >= retryAfter else {
                return nil
            }
            guard startIfNeeded() else {
                retryAfter = Date().addingTimeInterval(30)
                return nil
            }

            if !initialized {
                // Recent Codex app-server builds can delay the initialize response until
                // a later request is sent. Treat initialize as a best-effort handshake
                // instead of blocking the rate-limit read path on it.
                _ = initialize(timeout: min(timeout, 0.5))
                initialized = true
            }

            guard
                let message = sendRequest(method: "account/rateLimits/read", params: NSNull(), timeout: timeout),
                let result = message["result"] as? [String: Any]
            else {
                stopLocked()
                return nil
            }

            return parseSnapshot(from: result)
        }
    }

    func stop() {
        queue.sync {
            stopLocked()
        }
    }

    private func initialize(timeout: TimeInterval) -> Bool {
        let params: [String: Any] = [
            "clientInfo": [
                "name": "codex-quota-widget",
                "title": "Codex Quota Widget",
                "version": "2.0",
            ],
            "capabilities": [
                "experimentalApi": true,
                "optOutNotificationMethods": [],
            ],
        ]

        return sendRequest(method: "initialize", params: params, timeout: timeout)?["result"] != nil
    }

    private func startIfNeeded() -> Bool {
        if process?.isRunning == true, inputPipe != nil {
            return true
        }

        stopLocked()

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = codexURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.environment = Self.childEnvironment()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { [weak self] terminated in
            guard let self else { return }
            self.lock.lock()
            self.initialized = false
            let stderrTail = self.errorBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            self.lock.unlock()

            let reason = terminated.terminationReason == .uncaughtSignal
                ? "signal \(terminated.terminationStatus)"
                : "exit \(terminated.terminationStatus)"
            let detail = stderrTail.isEmpty ? "" : " stderr=\(String(stderrTail.suffix(500)))"
            widgetLog("app-server terminated reason=\(reason)\(detail)")
        }

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handleOutput(data)
        }

        // Drain stderr so app-server warnings never block the child process.
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            guard let self else { return }
            self.lock.lock()
            self.errorBuffer.append(text)
            if self.errorBuffer.count > 2000 {
                self.errorBuffer = String(self.errorBuffer.suffix(2000))
            }
            self.lock.unlock()
        }

        do {
            try process.run()
        } catch {
            widgetLog("app-server failed to start: \(error.localizedDescription)")
            return false
        }
        widgetLog("app-server started url=\(codexURL.path)")

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
        self.outputBuffer = ""
        self.initialized = false
        return true
    }

    private func stopLocked() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        inputPipe?.fileHandleForWriting.closeFile()
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        outputBuffer = ""
        pendingResponses.removeAll()
        initialized = false
    }

    private func sendRequest(method: String, params: Any, timeout: TimeInterval) -> [String: Any]? {
        guard let inputPipe else {
            return nil
        }

        let requestID = nextRequestID
        nextRequestID += 1

        let pending = PendingResponse()
        lock.lock()
        pendingResponses[requestID] = pending
        lock.unlock()

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method,
            "params": params,
        ]

        guard
            JSONSerialization.isValidJSONObject(request),
            var data = try? JSONSerialization.data(withJSONObject: request)
        else {
            removePendingResponse(requestID)
            return nil
        }

        data.append(0x0A)
        guard process?.isRunning == true else {
            removePendingResponse(requestID)
            return nil
        }

        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            widgetLog("app-server write failed: \(error.localizedDescription)")
            retryAfter = Date().addingTimeInterval(10)
            removePendingResponse(requestID)
            stopLocked()
            return nil
        }

        let waitResult = pending.semaphore.wait(timeout: .now() + timeout)
        lock.lock()
        let message = pending.message
        pendingResponses[requestID] = nil
        lock.unlock()

        guard waitResult == .success else {
            return nil
        }
        return message
    }

    private func removePendingResponse(_ requestID: Int) {
        lock.lock()
        pendingResponses[requestID] = nil
        lock.unlock()
    }

    private func handleOutput(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            return
        }

        lock.lock()
        outputBuffer.append(text)

        while let newlineIndex = outputBuffer.firstIndex(of: "\n") {
            let line = String(outputBuffer[..<newlineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            outputBuffer.removeSubrange(...newlineIndex)
            handleLineLocked(line)
        }

        lock.unlock()
    }

    private func handleLineLocked(_ line: String) {
        guard
            !line.isEmpty,
            let data = line.data(using: .utf8),
            let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let requestID = (message["id"] as? NSNumber)?.intValue ?? Int("\(message["id"] ?? "")"),
            let pending = pendingResponses[requestID]
        else {
            return
        }

        pending.message = message
        pending.semaphore.signal()
    }

    private func parseSnapshot(from result: [String: Any]) -> QuotaSnapshot? {
        let rateLimitsByID = result["rateLimitsByLimitId"] as? [String: Any]
        let codexRateLimits = rateLimitsByID?["codex"] as? [String: Any]
        let fallbackRateLimits = result["rateLimits"] as? [String: Any]

        guard
            let rateLimits = codexRateLimits ?? fallbackRateLimits,
            (rateLimits["limitId"] as? String) == "codex"
        else {
            return nil
        }

        // 已过重置时间的窗口不再展示，剩余窗口顺位提升，避免 5h 重置后整条快照不可用。
        let windows = ["primary", "secondary"]
            .compactMap { rateLimits[$0] as? [String: Any] }
            .compactMap(parseWindow(_:))
            .filter { window in
                guard let resetsAt = window.resetsAt else { return true }
                return resetsAt > Date()
            }
        guard let primary = windows.first else {
            return nil
        }
        let secondary = windows.dropFirst().first { $0.label != primary.label }

        return QuotaSnapshot(
            sourceFileName: "Codex app-server",
            eventTimestamp: Date(),
            detectedAt: Date(),
            planType: rateLimits["planType"] as? String,
            primary: primary,
            secondary: secondary
        )
    }

    private func parseWindow(_ payload: [String: Any]) -> WindowQuota? {
        let windowMinutes = (payload["windowDurationMins"] as? NSNumber)?.intValue
            ?? Int("\(payload["windowDurationMins"] ?? "")")
        guard let windowMinutes else {
            return nil
        }

        let usedPercent = clampPercent(payload["usedPercent"])
        let resetsEpoch = (payload["resetsAt"] as? NSNumber)?.intValue
            ?? Int("\(payload["resetsAt"] ?? "")")

        return WindowQuota(
            label: windowLabel(minutes: windowMinutes),
            usedPercent: usedPercent,
            remainingPercent: max(0, 100 - usedPercent),
            resetsAt: resetsEpoch.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private func clampPercent(_ value: Any?) -> Double {
        guard let value else { return 0 }
        let number = (value as? NSNumber)?.doubleValue ?? Double("\(value)") ?? 0
        return min(max(number, 0), 100)
    }

    private func windowLabel(minutes: Int) -> String {
        switch minutes {
        case 300:
            return "5h"
        case 10080:
            return "7d"
        case let value where value % 1440 == 0:
            return "\(value / 1440)d"
        case let value where value % 60 == 0:
            return "\(value / 60)h"
        default:
            return "\(minutes)m"
        }
    }

    /// 从访达启动时 PATH 只有系统目录，Homebrew 的 codex 是 Node 脚本，
    /// 必须把 node 所在目录补进子进程环境，否则子进程会立刻退出。
    private static func childEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let requiredEntries = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]

        var entries = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for entry in requiredEntries where !entries.contains(entry) {
            entries.append(entry)
        }
        environment["PATH"] = entries.joined(separator: ":")
        return environment
    }

    private static func discoverCodexURL() -> URL {
        let fileManager = FileManager.default
        for candidate in codexURLCandidates() where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        return URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")
    }

    private static func codexURLCandidates() -> [URL] {
        var candidates: [URL] = []

        if let overridePath = ProcessInfo.processInfo.environment["CODEX_QUOTA_WIDGET_CODEX_PATH"], !overridePath.isEmpty {
            candidates.append(URL(fileURLWithPath: overridePath))
        }

        let applicationDirectories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
        let appNames = ["Codex.app", "ChatGPT.app"]

        for directory in applicationDirectories {
            for appName in appNames {
                candidates.append(
                    directory
                        .appendingPathComponent(appName, isDirectory: true)
                        .appendingPathComponent("Contents/Resources/codex")
                )
            }
        }

        // 只装了 CLI 版 codex 时（Homebrew / npm），从 Finder 启动的应用拿不到 PATH，需要显式补上常见安装位置。
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        candidates.append(contentsOf: [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            homeDirectory.appendingPathComponent(".local/bin/codex"),
        ])

        return candidates
    }
}
