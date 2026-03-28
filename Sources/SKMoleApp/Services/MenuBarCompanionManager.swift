import AppKit
import Foundation
import ServiceManagement
import SKMoleShared

@MainActor
final class MenuBarCompanionManager {
    private var loginItemService: SMAppService {
        SMAppService.loginItem(identifier: MenuBarHelperConstants.bundleIdentifier)
    }

    func status(registrationError: String? = nil) -> MenuBarCompanionState {
        guard helperBundleURL() != nil else {
            return .unavailable
        }

        let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: MenuBarHelperConstants.bundleIdentifier).isEmpty

        switch loginItemService.status {
        case .enabled:
            return MenuBarCompanionState(
                summary: isRunning ? "Running" : "Registered",
                detail: isRunning
                    ? "The menu bar companion is running independently and is registered to relaunch at login."
                    : "The menu bar companion is registered to relaunch at login. Open SK Mole once to start it in the current session if needed.",
                isRunning: isRunning,
                isRegistered: true,
                requiresApproval: false
            )
        case .requiresApproval:
            return MenuBarCompanionState(
                summary: isRunning ? "Running, approval pending" : "Approval required",
                detail: registrationError
                    ?? "macOS still needs approval in Login Items before the companion can relaunch automatically.",
                isRunning: isRunning,
                isRegistered: false,
                requiresApproval: true
            )
        case .notRegistered:
            return MenuBarCompanionState(
                summary: isRunning ? "Running manually" : "Not registered",
                detail: registrationError
                    ?? "The companion can still be launched manually for this session, but it is not yet configured to relaunch automatically at login.",
                isRunning: isRunning,
                isRegistered: false,
                requiresApproval: false
            )
        case .notFound:
            return .unavailable
        @unknown default:
            return MenuBarCompanionState(
                summary: "Unknown",
                detail: registrationError ?? "The menu bar companion returned an unrecognized ServiceManagement status.",
                isRunning: isRunning,
                isRegistered: false,
                requiresApproval: false
            )
        }
    }

    func launchIfNeeded() {
        guard !isRunning else { return }
        guard let helperBundleURL = helperBundleURL() else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false

        NSWorkspace.shared.openApplication(at: helperBundleURL, configuration: configuration)
    }

    func terminateRunningHelper() {
        NSRunningApplication.runningApplications(withBundleIdentifier: MenuBarHelperConstants.bundleIdentifier).forEach {
            $0.terminate()
        }
    }

    func registerForLaunchAtLogin() throws {
        try loginItemService.register()
    }

    func unregisterFromLaunchAtLogin() throws {
        try loginItemService.unregister()
    }

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: MenuBarHelperConstants.bundleIdentifier).isEmpty
    }

    private func helperBundleURL() -> URL? {
        let mainBundleURL = Bundle.main.bundleURL
        let helperURL = mainBundleURL.appendingPathComponent(MenuBarHelperConstants.bundleRelativePath)
        return FileManager.default.fileExists(atPath: helperURL.path) ? helperURL : nil
    }
}
