import AppKit
import Darwin
import Foundation

// app-server 子进程退出后，继续写管道会触发 SIGPIPE；默认动作是直接杀掉整个应用。
// 忽略它，让写入返回 EPIPE 并在 provider 里按失败处理。
signal(SIGPIPE, SIG_IGN)

let snapshotService = QuotaSnapshotService()

// 状态目录和日志函数要先于 --once 定义，否则 provider 在诊断模式下写日志时读到未初始化的全局变量。
let stateDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".codex-quota-widget")
try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)

func widgetLog(_ message: String) {
    let fileURL = stateDirectory.appendingPathComponent("widget.log")
    let formatter = ISO8601DateFormatter()
    let line = "[\(formatter.string(from: Date()))] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }

    let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
    let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
    if size > 512 * 1024 {
        try? FileManager.default.removeItem(at: fileURL)
    } else if !FileManager.default.fileExists(atPath: fileURL.path) {
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }

    guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
    handle.seekToEndOfFile()
    handle.write(data)
    try? handle.close()
}

if CommandLine.arguments.contains("--once") {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    if let snapshot = snapshotService.latestSnapshot(), let data = try? encoder.encode(snapshot) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
        exit(EXIT_SUCCESS)
    } else {
        FileHandle.standardError.write("No quota snapshot found in ~/.codex/sessions\n".data(using: .utf8)!)
        exit(EXIT_FAILURE)
    }
}

// LaunchAgent 版与应用版共用一把文件锁，只允许一个浮窗实例运行。
let lockURL = stateDirectory.appendingPathComponent("instance.lock")
let lockFD = open(lockURL.path, O_CREAT | O_RDWR, 0o644)

// 退出后立刻再次打开时，旧进程可能还没释放锁，短暂重试避免用户看到“闪退”。
var lockAcquired = false
if lockFD >= 0 {
    let deadline = Date().addingTimeInterval(2)
    repeat {
        if flock(lockFD, LOCK_EX | LOCK_NB) == 0 {
            lockAcquired = true
            break
        }
        usleep(100_000)
    } while Date() < deadline
}

if lockFD >= 0, !lockAcquired {
    widgetLog("duplicate launch blocked: pid=\(getpid()) bundle=\(Bundle.main.bundleURL.path)")
    DistributedNotificationCenter.default().postNotificationName(
        WidgetNotifications.showWidget,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )

    // 从磁盘映像或解压目录再开一份时，给出明确提示，而不是看起来像闪退。
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
    let otherPath = running.first?.bundleURL?.resolvingSymlinksInPath().path
    let currentPath = Bundle.main.bundleURL.resolvingSymlinksInPath().path
    if let otherPath, otherPath != currentPath {
        let language = WidgetStateStore().load().language ?? .english
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = language.text(
            "Codex Quota Widget Is Already Running",
            "Codex Quota Widget 已在运行"
        )
        alert.informativeText = language.text(
            "The running instance is:\n\(otherPath)\n\nUse that instance, or quit it before opening this copy.",
            "当前实例来自：\n\(otherPath)\n\n请直接使用这个实例，或先退出它再打开新的副本。"
        )
        alert.addButton(withTitle: language.text("OK", "好"))
        alert.runModal()
    }

    FileHandle.standardError.write("Another CodexQuotaWidget instance is already running.\n".data(using: .utf8)!)
    exit(EXIT_SUCCESS)
}

widgetLog("launched pid=\(getpid()) bundle=\(Bundle.main.bundleURL.path)")

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
