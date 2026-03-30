import Foundation

enum SidebarSection: String, CaseIterable, Hashable, Identifiable {
    case dashboard
    case homebrew
    case network
    case quarantine
    case smartCare
    case cleanup
    case uninstall
    case storage
    case optimize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .homebrew: "Homebrew"
        case .network: "Network"
        case .quarantine: "Quarantine"
        case .smartCare: "Smart Care"
        case .cleanup: "Cleanup"
        case .uninstall: "Uninstaller"
        case .storage: "Storage"
        case .optimize: "Optimize"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.50percent"
        case .homebrew: "cup.and.saucer.fill"
        case .network: "network"
        case .quarantine: "shield.slash"
        case .smartCare: "sparkles.rectangle.stack.fill"
        case .cleanup: "sparkles.rectangle.stack"
        case .uninstall: "xmark.app"
        case .storage: "internaldrive"
        case .optimize: "bolt.badge.clock"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: "Real-time system health and fast actions"
        case .homebrew: "Manage Homebrew packages, casks, services, and maintenance"
        case .network: "On-demand process, connection, and remote-host inspection"
        case .quarantine: "Review quarantined apps and clear com.apple.quarantine deliberately"
        case .smartCare: "Guided recommendations across cleanup, storage, and health"
        case .cleanup: "Preview reclaimable space before moving items to Trash"
        case .uninstall: "Remove apps and user-domain remnants safely"
        case .storage: "Surface heavy folders and large files"
        case .optimize: "Refresh caches and user-facing system services"
        }
    }

    var shortcutKey: Character {
        switch self {
        case .dashboard: "1"
        case .homebrew: "2"
        case .network: "3"
        case .quarantine: "4"
        case .smartCare: "5"
        case .cleanup: "6"
        case .uninstall: "7"
        case .storage: "8"
        case .optimize: "9"
        }
    }

    init?(urlSlug: String) {
        switch urlSlug {
        case "dashboard":
            self = .dashboard
        case "homebrew", "brew":
            self = .homebrew
        case "network":
            self = .network
        case "quarantine":
            self = .quarantine
        case "smart-care", "smartcare":
            self = .smartCare
        case "cleanup":
            self = .cleanup
        case "uninstall", "uninstaller":
            self = .uninstall
        case "storage":
            self = .storage
        case "optimize":
            self = .optimize
        default:
            return nil
        }
    }
}
