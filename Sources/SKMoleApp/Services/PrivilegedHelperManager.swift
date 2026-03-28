import Foundation
import ServiceManagement
import SKMoleShared

@MainActor
final class PrivilegedHelperManager {
    private var daemonService: SMAppService {
        SMAppService.daemon(plistName: PrivilegedHelperConstants.plistName)
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

    func ping() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let bridge = XPCReplyBridge<String>(continuation: continuation)
            let connection = configuredConnection()
            bridge.connection = connection

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

    func run(_ task: PrivilegedMaintenanceTask) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let bridge = XPCReplyBridge<String>(continuation: continuation)
            let connection = configuredConnection()
            bridge.connection = connection

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

    private func configuredConnection() -> NSXPCConnection {
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
    var connection: NSXPCConnection?

    init(continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
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
        connection?.invalidate()
        body()
    }
}

private enum PrivilegedHelperError: LocalizedError {
    case invalidProxy
    case remoteFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidProxy:
            "The privileged helper connection could not be created."
        case let .remoteFailure(message):
            message
        }
    }
}
