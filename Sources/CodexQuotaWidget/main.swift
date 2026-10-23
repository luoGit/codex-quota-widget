import AppKit
import Darwin
import Foundation

let snapshotService = QuotaSnapshotService()

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
let lockURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".codex-quota-widget/instance.lock")
try? FileManager.default.createDirectory(
    at: lockURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
let lockFD = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
if lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    FileHandle.standardError.write("Another CodexQuotaWidget instance is already running.\n".data(using: .utf8)!)
    exit(EXIT_SUCCESS)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
