import Foundation
import Security
import SKMoleShared

private final class PrivilegedTaskRunner: @unchecked Sendable {
    private let purgeableReclaimTargetBytes = "10737418240"

    func run(task: PrivilegedMaintenanceTask) async throws -> String {
        guard getuid() == 0 else {
            throw HelperError.rootRequired
        }

        switch task {
        case .flushDNSCache:
            let flushOutput = try await runProcess(
                executable: "/usr/bin/dscacheutil",
                arguments: ["-flushcache"]
            )
            let mdnsOutput = try await runProcess(
                executable: "/usr/bin/killall",
                arguments: ["-HUP", "mDNSResponder"]
            )

            return [flushOutput, mdnsOutput]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
                .ifEmpty("DNS cache refresh completed.")

        case .freePurgeableSpace:
            let output = try await runProcess(
                executable: "/usr/bin/tmutil",
                arguments: ["thinlocalsnapshots", "/", purgeableReclaimTargetBytes, "4"]
            )
            return output.ifEmpty("macOS finished thinning local snapshots to reclaim purgeable space where possible.")

        case .runPeriodicDaily:
            let output = try await runProcess(
                executable: "/usr/sbin/periodic",
                arguments: ["daily"]
            )
            return output.ifEmpty("Daily periodic maintenance completed.")
        }
    }

    private func runProcess(executable: String, arguments: [String]) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw HelperError.missingExecutable(executable)
        }

        let outputLimit = 1 * 1_024 * 1_024
        let timeout: TimeInterval = executable.hasSuffix("/tmutil") ? 90 : 30
        let result = try await ProcessRunner.run(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            maxOutputBytes: outputLimit
        )
        let output = result.output

        guard result.terminationStatus == 0 else {
            throw HelperError.commandFailed(output.isEmpty ? "\(executable) exited with status \(result.terminationStatus)." : output)
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

        let replyBox = HelperReplyBox(reply)
        Task.detached(priority: .utility) { [runner, replyBox] in
            do {
                let output = try await runner.run(task: task)
                replyBox.send(success: true, message: output)
            } catch {
                replyBox.send(success: false, message: error.localizedDescription)
            }
        }
    }
}

private final class HelperReplyBox: @unchecked Sendable {
    private let reply: (Bool, String) -> Void

    init(_ reply: @escaping (Bool, String) -> Void) {
        self.reply = reply
    }

    func send(success: Bool, message: String) {
        reply(success, message)
    }
}

private final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard HelperClientVerifier.isTrusted(connection: newConnection) else {
            NSLog("SK Mole privileged helper rejected untrusted XPC client with pid %d", newConnection.processIdentifier)
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: PrivilegedHelperXPCProtocol.self)
        newConnection.exportedObject = PrivilegedHelperService()
        newConnection.resume()
        return true
    }
}

private enum HelperClientVerifier {
    private static let allowedClientIdentifiers: Set<String> = [
        MenuBarHelperConstants.mainAppBundleIdentifier
    ]

    static func isTrusted(connection: NSXPCConnection) -> Bool {
        guard let snapshot = signingSnapshot(forGuestWithPID: connection.processIdentifier),
              isCodeValid(snapshot.code),
              let info = snapshot.info,
              let identifier = info[kSecCodeInfoIdentifier as String] as? String,
              allowedClientIdentifiers.contains(identifier) else {
            return false
        }

        let clientTeam = info[kSecCodeInfoTeamIdentifier as String] as? String
        let helperTeam = selfSigningInfo().flatMap { $0[kSecCodeInfoTeamIdentifier as String] as? String }

        if let clientTeam, let helperTeam, !clientTeam.isEmpty, !helperTeam.isEmpty {
            return clientTeam == helperTeam
                && satisfiesDesignatedRequirement(code: snapshot.code, identifier: identifier, teamIdentifier: helperTeam)
        }

        // Local ad-hoc builds do not carry a TeamIdentifier. Keep them usable for
        // development, but require a real SK Mole app bundle shape rather than only
        // trusting an arbitrary process that reused the bundle identifier.
        return isRecognizedDevelopmentClient(info: info)
    }

    private static func signingSnapshot(forGuestWithPID pid: pid_t) -> (code: SecCode, info: [String: Any]?)? {
        let attributes = [kSecGuestAttributePid as String: pid] as CFDictionary
        var code: SecCode?
        let guestStatus = SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code)
        guard guestStatus == errSecSuccess, let code else {
            return nil
        }

        return (code, signingInfo(for: code))
    }

    private static func selfSigningInfo() -> [String: Any]? {
        var code: SecCode?
        let status = SecCodeCopySelf(SecCSFlags(), &code)
        guard status == errSecSuccess, let code else {
            return nil
        }

        return signingInfo(for: code)
    }

    private static func signingInfo(for code: SecCode) -> [String: Any]? {
        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode)
        guard staticStatus == errSecSuccess, let staticCode else {
            return nil
        }

        var info: CFDictionary?
        let status = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        )
        guard status == errSecSuccess else {
            return nil
        }

        return info as? [String: Any]
    }

    private static func isCodeValid(_ code: SecCode) -> Bool {
        SecCodeCheckValidityWithErrors(
            code,
            SecCSFlags(rawValue: kSecCSBasicValidateOnly),
            nil,
            nil
        ) == errSecSuccess
    }

    private static func satisfiesDesignatedRequirement(
        code: SecCode,
        identifier: String,
        teamIdentifier: String
    ) -> Bool {
        guard let identifier = requirementLiteral(identifier),
              let teamIdentifier = requirementLiteral(teamIdentifier) else {
            return false
        }

        let requirementText = #"anchor apple generic and identifier "\#(identifier)" and certificate leaf[subject.OU] = "\#(teamIdentifier)""# as CFString
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement else {
            return false
        }

        return SecCodeCheckValidityWithErrors(
            code,
            SecCSFlags(rawValue: kSecCSBasicValidateOnly),
            requirement,
            nil
        ) == errSecSuccess
    }

    private static func isRecognizedDevelopmentClient(info: [String: Any]) -> Bool {
        guard let executableURL = info[kSecCodeInfoMainExecutable as String] as? URL else {
            return false
        }

        let components = executableURL.standardizedFileURL.pathComponents
        guard Array(components.suffix(4)) == ["SK Mole.app", "Contents", "MacOS", "SK Mole"] else {
            return false
        }

        let bundleURL = executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return Bundle(url: bundleURL)?.bundleIdentifier == MenuBarHelperConstants.mainAppBundleIdentifier
    }

    private static func requirementLiteral(_ value: String) -> String? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_")
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return value
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
