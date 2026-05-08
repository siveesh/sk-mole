import Foundation

enum StartupItemKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case userLaunchAgent
    case systemLaunchAgent
    case systemLaunchDaemon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userLaunchAgent: "User Launch Agent"
        case .systemLaunchAgent: "System Launch Agent"
        case .systemLaunchDaemon: "System Launch Daemon"
        }
    }

    var symbol: String {
        switch self {
        case .userLaunchAgent: "person.crop.circle.badge.plus"
        case .systemLaunchAgent: "gearshape.2"
        case .systemLaunchDaemon: "lock.shield"
        }
    }

    var isManageable: Bool {
        self == .userLaunchAgent
    }
}

struct StartupItem: Identifiable, Hashable, Sendable {
    let label: String
    let displayName: String
    let url: URL
    let program: String?
    let kind: StartupItemKind
    let isLoaded: Bool
    let isDisabled: Bool
    let runsAtLoad: Bool
    let keepAlive: Bool
    let lastModified: Date?

    var id: String { url.path }

    var canToggle: Bool {
        kind.isManageable
    }

    var stateTitle: String {
        if !canToggle {
            return "Review"
        }

        if isDisabled {
            return "Disabled"
        }

        return isLoaded ? "Loaded" : "Available"
    }

    var stateDetail: String {
        if !canToggle {
            return "This item lives outside the user domain, so SK Mole only surfaces it for review."
        }

        if isDisabled {
            return "Disabled for your login session and future launches until re-enabled."
        }

        if isLoaded {
            return "Currently loaded for your user session."
        }

        return "Enabled on disk but not currently loaded."
    }
}
