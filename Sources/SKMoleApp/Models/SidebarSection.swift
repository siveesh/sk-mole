import Foundation

enum SidebarSection: String, CaseIterable, Hashable, Identifiable {
    case dashboard
    case homebrew
    case fileIntelligence
    case network
    case processes
    case quarantine
    case orphans
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
        case .fileIntelligence: "File Intelligence"
        case .network: "Network"
        case .processes: "Processes"
        case .quarantine: "Quarantine"
        case .orphans: "Orphans"
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
        case .fileIntelligence: "doc.text.viewfinder"
        case .network: "network"
        case .processes: "list.bullet.rectangle.portrait"
        case .quarantine: "shield.slash"
        case .orphans: "questionmark.folder"
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
        case .fileIntelligence: "Use Magika to classify files by content and scan folders recursively"
        case .network: "On-demand process, connection, and remote-host inspection"
        case .processes: "Inspect active processes and safely terminate user-owned work"
        case .quarantine: "Review quarantined apps and clear com.apple.quarantine deliberately"
        case .orphans: "Find leftover app support files from apps that no longer appear installed"
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
        case .fileIntelligence: "f"
        case .network: "3"
        case .processes: "p"
        case .quarantine: "4"
        case .orphans: "5"
        case .smartCare: "6"
        case .cleanup: "7"
        case .uninstall: "8"
        case .storage: "9"
        case .optimize: "0"
        }
    }

    init?(urlSlug: String) {
        switch urlSlug {
        case "dashboard":
            self = .dashboard
        case "homebrew", "brew":
            self = .homebrew
        case "file-intelligence", "file-intel", "magika":
            self = .fileIntelligence
        case "network":
            self = .network
        case "processes", "process-inspector", "activity":
            self = .processes
        case "quarantine":
            self = .quarantine
        case "orphans", "orphan-review", "leftovers":
            self = .orphans
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
