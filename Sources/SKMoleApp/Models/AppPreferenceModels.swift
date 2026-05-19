import Foundation

enum StartupPreference: String, CaseIterable, Identifiable {
    case rememberLast
    case dashboard
    case updates
    case homebrew
    case fileIntelligence
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
        case .rememberLast: "Remember last section"
        case .dashboard: "Always open Dashboard"
        case .updates: "Always open Updates"
        case .homebrew: "Always open Homebrew"
        case .fileIntelligence: "Always open File Intelligence"
        case .processes: "Always open Processes"
        case .quarantine: "Always open Quarantine"
        case .orphans: "Always open Orphans"
        case .smartCare: "Always open Smart Care"
        case .cleanup: "Always open Cleanup"
        case .uninstall: "Always open Uninstaller"
        case .storage: "Always open Storage"
        case .optimize: "Always open Optimize"
        }
    }

    func resolve(lastSelection: SidebarSection?) -> SidebarSection {
        switch self {
        case .rememberLast:
            return lastSelection ?? .dashboard
        case .dashboard:
            return .dashboard
        case .updates:
            return .updates
        case .homebrew:
            return .homebrew
        case .fileIntelligence:
            return .fileIntelligence
        case .processes:
            return .processes
        case .quarantine:
            return .quarantine
        case .orphans:
            return .orphans
        case .smartCare:
            return .smartCare
        case .cleanup:
            return .cleanup
        case .uninstall:
            return .uninstall
        case .storage:
            return .storage
        case .optimize:
            return .optimize
        }
    }
}

enum FullDiskAccessStatus: String, Hashable {
    case unknown
    case limited
    case granted

    var title: String {
        switch self {
        case .unknown: "Unknown"
        case .limited: "Recommended"
        case .granted: "Enabled"
        }
    }

    var detail: String {
        switch self {
        case .unknown:
            return "SK Mole could not verify a protected location on this Mac yet, so it will keep using its careful user-approved paths."
        case .limited:
            return "Open Privacy & Security once to give SK Mole broader read access for deeper scans without repeated folder-level interruptions."
        case .granted:
            return "Protected user folders appear readable, so deeper scans should work without repeated access interruptions."
        }
    }

    var needsAttention: Bool {
        self != .granted
    }
}
