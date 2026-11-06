import Foundation
import UIKit

/// Temporary diagnostics: records what the app was doing, and the reason of any
/// Objective-C exception (e.g. from AVFoundation), so it can be shown on the next launch.
enum CrashReporter {
    private static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static var exceptionURL: URL { docs.appendingPathComponent("crash_exception.txt") }
    static var logURL: URL { docs.appendingPathComponent("session_log.txt") }
    static var previousLogURL: URL { docs.appendingPathComponent("session_log_previous.txt") }
    static var runningFlagURL: URL { docs.appendingPathComponent("session_running.flag") }

    private static var previousReport: String?
    private static var observers: [NSObjectProtocol] = []

    static func install() {
        let fm = FileManager.default
        let previousSessionDidNotEndCleanly = fm.fileExists(atPath: runningFlagURL.path)

        // Rotate the log from the previous session
        try? fm.removeItem(at: previousLogURL)
        if fm.fileExists(atPath: logURL.path) { try? fm.moveItem(at: logURL, to: previousLogURL) }

        var report = ""
        if let exception = try? String(contentsOf: exceptionURL, encoding: .utf8) {
            report += "EXCEPTION:\n\(exception)\n\n"
            try? fm.removeItem(at: exceptionURL)
        }
        if !report.isEmpty || previousSessionDidNotEndCleanly,
           let lastLog = try? String(contentsOf: previousLogURL, encoding: .utf8) {
            report += "LAST ACTIONS BEFORE THE CRASH:\n" + lastLog.split(separator: "\n").suffix(30).joined(separator: "\n")
        }
        previousReport = report.isEmpty ? nil : report

        fm.createFile(atPath: runningFlagURL.path, contents: Data())
        // Leaving the app normally is not a crash
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            try? FileManager.default.removeItem(at: CrashReporter.runningFlagURL)
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            FileManager.default.createFile(atPath: CrashReporter.runningFlagURL.path, contents: Data())
        })

        NSSetUncaughtExceptionHandler { exception in
            let text = "\(exception.name.rawValue)\n\(exception.reason ?? "(no reason)")\n\n"
                + exception.callStackSymbols.prefix(25).joined(separator: "\n")
            try? text.write(to: CrashReporter.exceptionURL, atomically: true, encoding: .utf8)
        }
    }

    static func reportFromPreviousSession() -> String? { previousReport }

    static func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let line = "\(formatter.string(from: Date()))  \(message)\n"
        print(line, terminator: "")
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logURL)
        }
    }
}
