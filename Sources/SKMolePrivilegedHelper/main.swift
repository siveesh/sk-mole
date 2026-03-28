import Foundation
import SKMoleShared

private final class PrivilegedTaskRunner {
    private let purgeableReclaimTargetBytes = "10737418240"

    func run(task: PrivilegedMaintenanceTask) throws -> String {
        guard getuid() == 0 else {
            throw HelperError.rootRequired
        }

        switch task {
        case .flushDNSCache:
            let flushOutput = try runProcess(
                executable: "/usr/bin/dscacheutil",
                arguments: ["-flushcache"]
            )
            let mdnsOutput = try runProcess(
                executable: "/usr/bin/killall",
                arguments: ["-HUP", "mDNSResponder"]
            )

            return [flushOutput, mdnsOutput]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
                .ifEmpty("DNS cache refresh completed.")

        case .freePurgeableSpace:
            let output = try runProcess(
                executable: "/usr/bin/tmutil",
                arguments: ["thinlocalsnapshots", "/", purgeableReclaimTargetBytes, "4"]
            )
            return output.ifEmpty("macOS finished thinning local snapshots to reclaim purgeable space where possible.")

        case .runPeriodicDaily:
            let output = try runProcess(
                executable: "/usr/sbin/periodic",
                arguments: ["daily"]
            )
            return output.ifEmpty("Daily periodic maintenance completed.")
        }
    }

    private func runProcess(executable: String, arguments: [String]) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw HelperError.missingExecutable(executable)
        }

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw HelperError.commandFailed(output.isEmpty ? "\(executable) exited with status \(process.terminationStatus)." : output)
        }

        return output
    }
}

private final class PrivilegedHelperService: NSObject, PrivilegedHelperXPCProtocol {
    private let runner = PrivilegedTaskRunner()

    func ping(withReply reply: @escaping (String) -> Void) {
        reply("ready")
    }

    func runTask(identifier: String, withReply reply: @escaping (Bool, String) -> Void) {
        guard let task = PrivilegedMaintenanceTask(rawValue: identifier) else {
            reply(false, "Unsupported privileged task identifier: \(identifier)")
            return
        }

        do {
            let output = try runner.run(task: task)
            reply(true, output)
        } catch {
            reply(false, error.localizedDescription)
        }
    }
}

private final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: PrivilegedHelperXPCProtocol.self)
        newConnection.exportedObject = PrivilegedHelperService()
        newConnection.resume()
        return true
    }
}

private enum HelperError: LocalizedError {
    case rootRequired
    case missingExecutable(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .rootRequired:
            "This helper must run as root."
        case let .missingExecutable(path):
            "Required executable not found: \(path)"
        case let .commandFailed(output):
            output
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

private let listener = NSXPCListener(machServiceName: PrivilegedHelperConstants.daemonLabel)
private let delegate = HelperDelegate()
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
