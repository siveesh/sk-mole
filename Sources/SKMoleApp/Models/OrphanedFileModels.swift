import Foundation

enum OrphanedFileCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case applicationSupport
    case caches
    case preferences
    case containers
    case groupContainers
    case logs
    case savedState
    case launchAgents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applicationSupport: "Application Support"
        case .caches: "Caches"
        case .preferences: "Preferences"
        case .containers: "Containers"
        case .groupContainers: "Group Containers"
        case .logs: "Logs"
        case .savedState: "Saved State"
        case .launchAgents: "Launch Agents"
        }
    }

    var symbol: String {
        switch self {
        case .applicationSupport: "shippingbox"
        case .caches: "externaldrive.badge.timemachine"
        case .preferences: "slider.horizontal.3"
        case .containers: "square.3.layers.3d"
        case .groupContainers: "square.stack.3d.down.right"
        case .logs: "doc.text.magnifyingglass"
        case .savedState: "clock.arrow.circlepath"
        case .launchAgents: "person.crop.circle.badge.plus"
        }
    }

    var subtitle: String {
        switch self {
        case .applicationSupport:
            "Support folders whose owning app no longer looks installed."
        case .caches:
            "Cache directories left behind after an app appears to be gone."
        case .preferences:
            "Preference plists tied to bundle identifiers that no longer resolve."
        case .containers:
            "Sandbox containers whose owning app no longer appears installed."
        case .groupContainers:
            "Shared containers that still reference missing app identifiers."
        case .logs:
            "App-specific logs that still occupy space after uninstall."
        case .savedState:
            "Saved window state for apps that are no longer present."
        case .launchAgents:
            "Per-user background launch agents that likely belong to removed apps."
        }
    }
}

struct OrphanedFileCandidate: Identifiable, Hashable, Sendable {
    let url: URL
    let displayName: String
    let identifierToken: String
    let category: OrphanedFileCategory
    let sizeBytes: UInt64
    let lastModified: Date?
    let rationale: String

    var id: String { url.path }
}
