import Foundation
import ServiceManagement
import SKMoleShared

struct PrivilegedHelperManager: Sendable {
    private var daemonService: SMAppService {
        SMAppService.daemon(plistName: PrivilegedHelperConstants.plistName)
    }

    private var helperExecutableURL: URL? {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/HelperTools/\(PrivilegedHelperConstants.helperExecutableName)")
    }

    func status() -> PrivilegedHelperState {
        switch daemonService.status {
        case .enabled:
            PrivilegedHelperState(
                summary: "Installed",
                detail: "The privileged helper is registered and available for admin-only maintenance.",
                isEnabled: true,
                requiresApproval: false
            )
        case .requiresApproval:
            PrivilegedHelperState(
                summary: "Approval required",
                detail: "macOS still needs approval for the helper registration in Login Items or system settings.",
                isEnabled: false,
                requiresApproval: true
            )
        case .notFound:
            PrivilegedHelperState(
                summary: "Bundle assets missing",
                detail: "The packaged app does not currently contain the helper plist or helper executable.",
                isEnabled: false,
                requiresApproval: false
            )
        case .notRegistered:
            .unavailable
        @unknown default:
            PrivilegedHelperState(
                summary: "Unknown",
                detail: "The helper returned an unrecognized ServiceManagement status.",
                isEnabled: false,
                requiresApproval: false
            )
        }
    }

    func register() throws -> PrivilegedHelperState {
        try daemonService.register()
        return status()
    }

    func unregister() throws -> PrivilegedHelperState {
        try daemonService.unregister()
        return status()
    }

    func diagnosticSummary() -> String? {
        if let signingIssue = signingIssueSummary() {
            return signingIssue
        }

        guard FileManager.default.isExecutableFile(atPath: "/bin/launchctl") else {
            return nil
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/\(PrivilegedHelperConstants.daemonLabel)"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !output.isEmpty else {
            return nil
        }

        let interestingPrefixes = [
            "state =",
            "path =",
            "program =",
            "last exit code =",
            "reason ="
        ]
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                interestingPrefixes.contains(where: { line.hasPrefix($0) })
            }

        if !lines.isEmpty {
            return "launchctl: " + lines.joined(separator: " | ")
        }

        if process.terminationStatus != 0 {
            return "launchctl: \(output)"
        }

        return nil
    }

    private func signingIssueSummary() -> String? {
        if let helperExecutableURL,
           let helperSignature = signatureSummary(for: helperExecutableURL),
           helperSignature.requiresTrustedSigning {
            return "The embedded privileged helper is \(helperSignature.signatureDescription). macOS blocks launch daemons unless they are signed with a trusted Apple certificate. Rebuild SK Mole with `SKMOLE_CODESIGN_IDENTITY` set to a valid `Apple Development` or `Developer ID Application` identity, then reinstall the helper."
        }

        if let appSignature = signatureSummary(for: Bundle.main.bundleURL),
           appSignature.requiresTrustedSigning {
            return "The main app bundle is \(appSignature.signatureDescription). The privileged helper cannot satisfy macOS launch constraints until the whole app is signed with a trusted Apple certificate and reinstalled."
        }

        return nil
    }

    private func signatureSummary(for url: URL) -> SignatureSummary? {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/codesign") || FileManager.default.fileExists(atPath: "/usr/bin/codesign") else {
            return nil
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=4", url.path]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)

        let signature = output
            .split(whereSeparator: \.isNewline)
            .first(where: { $0.hasPrefix("Signature=") })
            .map { entry in
                String(entry.split(separator: "=", maxSplits: 1).last ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

        let teamIdentifier = output
            .split(whereSeparator: \.isNewline)
            .first(where: { $0.hasPrefix("TeamIdentifier=") })
            .map { entry in
                String(entry.split(separator: "=", maxSplits: 1).last ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

        guard let signature else {
            return nil
        }

        let normalizedTeamIdentifier: String?
        if let teamIdentifier, !teamIdentifier.isEmpty, teamIdentifier != "not set" {
            normalizedTeamIdentifier = teamIdentifier
        } else {
            normalizedTeamIdentifier = nil
        }

        return SignatureSummary(signature: signature, teamIdentifier: normalizedTeamIdentifier)
    }

    nonisolated func ping() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let bridge = XPCReplyBridge<String>(continuation: continuation)
            let connection = configuredConnection()
            bridge.connection = connection
            bridge.startTimeout(seconds: 5)
            connection.invalidationHandler = { [weak bridge] in
                bridge?.fail(PrivilegedHelperError.connectionInvalidated)
            }
            connection.interruptionHandler = { [weak bridge] in
                bridge?.fail(PrivilegedHelperError.connectionInterrupted)
            }

            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                bridge.fail(error)
            }) as? PrivilegedHelperXPCProtocol else {
                bridge.fail(PrivilegedHelperError.invalidProxy)
                return
            }

            proxy.ping { reply in
                bridge.succeed(reply)
            }
        }
    }

    nonisolated func run(_ task: PrivilegedMaintenanceTask) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let bridge = XPCReplyBridge<String>(continuation: continuation)
            let connection = configuredConnection()
            bridge.connection = connection
            bridge.startTimeout(seconds: 10)
            connection.invalidationHandler = { [weak bridge] in
                bridge?.fail(PrivilegedHelperError.connectionInvalidated)
            }
            connection.interruptionHandler = { [weak bridge] in
                bridge?.fail(PrivilegedHelperError.connectionInterrupted)
            }

            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                bridge.fail(error)
            }) as? PrivilegedHelperXPCProtocol else {
                bridge.fail(PrivilegedHelperError.invalidProxy)
                return
            }

            proxy.runTask(identifier: task.rawValue) { succeeded, output in
                if succeeded {
                    bridge.succeed(output)
                } else {
                    bridge.fail(PrivilegedHelperError.remoteFailure(output))
                }
            }
        }
    }

    nonisolated private func configuredConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: PrivilegedHelperConstants.daemonLabel,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperXPCProtocol.self)
        return connection
    }
}

private final class XPCReplyBridge<Value: Sendable> {
    private let lock = NSLock()
    private var resumed = false
    private let continuation: CheckedContinuation<Value, Error>
    private var timeoutWorkItem: DispatchWorkItem?
    var connection: NSXPCConnection?

    init(continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func startTimeout(seconds: TimeInterval) {
        timeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.fail(PrivilegedHelperError.timeout)
        }
        timeoutWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(seconds, 1), execute: workItem)
    }

    func succeed(_ value: Value) {
        resolve {
            continuation.resume(returning: value)
        }
    }

    func fail(_ error: Error) {
        resolve {
            continuation.resume(throwing: error)
        }
    }

    private func resolve(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }

        guard !resumed else { return }
        resumed = true
        timeoutWorkItem?.cancel()
        connection?.invalidate()
        body()
    }
}

private enum PrivilegedHelperError: LocalizedError {
    case invalidProxy
    case remoteFailure(String)
    case timeout
    case connectionInterrupted
    case connectionInvalidated

    var errorDescription: String? {
        switch self {
        case .invalidProxy:
            "The privileged helper connection could not be created."
        case let .remoteFailure(message):
            message
        case .timeout:
            "The privileged helper did not respond in time."
        case .connectionInterrupted:
            "The privileged helper connection was interrupted."
        case .connectionInvalidated:
            "The privileged helper connection was invalidated."
        }
    }
}

private struct SignatureSummary {
    let signature: String
    let teamIdentifier: String?

    var requiresTrustedSigning: Bool {
        signature.caseInsensitiveCompare("adhoc") == .orderedSame || teamIdentifier == nil
    }

    var signatureDescription: String {
        if signature.caseInsensitiveCompare("adhoc") == .orderedSame {
            return "ad-hoc signed"
        }

        if let teamIdentifier {
            return "signed without a usable trusted team chain (\(teamIdentifier))"
        }

        return "signed without a usable trusted team chain"
    }
}
