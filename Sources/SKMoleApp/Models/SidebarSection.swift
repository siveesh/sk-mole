import Foundation

enum SidebarSection: String, CaseIterable, Hashable, Identifiable {
    case dashboard
    case smartCare
    case cleanup
    case uninstall
    case storage
    case optimize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
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
        case .smartCare: "2"
        case .cleanup: "3"
        case .uninstall: "4"
        case .storage: "5"
        case .optimize: "6"
        }
    }

    init?(urlSlug: String) {
        switch urlSlug {
        case "dashboard":
            self = .dashboard
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
