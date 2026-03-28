import Foundation

enum StorageNodeKind: String, Hashable {
    case root
    case volume
    case section
    case directory
    case package
    case file
    case remainder
}

enum StorageInspectionMode: String, CaseIterable, Identifiable, Hashable {
    case visible
    case hidden
    case admin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .admin: "Admin"
        }
    }

    var subtitle: String {
        switch self {
        case .visible: "Tracked folders and mounted volumes"
        case .hidden: "Purgeable estimates, local snapshots, and hidden volumes"
        case .admin: "System caches, VM, backups, and hidden system paths"
        }
    }
}

enum StorageVolumeKind: String, Hashable {
    case startup
    case internalDrive
    case externalDrive
    case networkDrive
    case readOnly

    var title: String {
        switch self {
        case .startup: "Startup"
        case .internalDrive: "Internal"
        case .externalDrive: "External"
        case .networkDrive: "Network"
        case .readOnly: "Read-only"
        }
    }

    var symbol: String {
        switch self {
        case .startup: "internaldrive.fill"
        case .internalDrive: "internaldrive"
        case .externalDrive: "externaldrive"
        case .networkDrive: "network"
        case .readOnly: "lock.circle"
        }
    }
}

enum StorageVolumeScanState: String, Hashable {
    case scanned
    case manualRequired

    var title: String {
        switch self {
        case .scanned: "Scanned"
        case .manualRequired: "Manual scan"
        }
    }

    var detail: String {
        switch self {
        case .scanned: "Folder map is ready"
        case .manualRequired: "Browse only after a manual scan"
        }
    }
}

struct StorageSection: Identifiable, Hashable {
    let title: String
    let icon: String
    let sizeBytes: UInt64
    let urls: [URL]

    var id: String { title }
}

struct StorageVolume: Identifiable, Hashable {
    let name: String
    let url: URL
    let totalBytes: UInt64
    let availableBytes: UInt64
    let kind: StorageVolumeKind
    let scanState: StorageVolumeScanState
    let browserRoot: StorageNode

    var id: String { url.path }

    var usedBytes: UInt64 {
        totalBytes > availableBytes ? totalBytes - availableBytes : 0
    }

    var freeRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(availableBytes) / Double(totalBytes)
    }

    var usageRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    var requiresManualScan: Bool {
        scanState == .manualRequired
    }
}

struct LargeFileEntry: Identifiable, Hashable {
    let url: URL
    let displayName: String
    let sizeBytes: UInt64
    let modifiedAt: Date?

    var id: String { url.path }
    var isAppBundle: Bool { url.pathExtension.lowercased() == "app" }
}

struct StorageInsight: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let detail: String
    let icon: String
    let sizeBytes: UInt64
    let url: URL?
    let requiresAdminContext: Bool
}

struct StorageNode: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let url: URL?
    let sizeBytes: UInt64
    let kind: StorageNodeKind
    let children: [StorageNode]

    var isDrillable: Bool {
        !children.isEmpty && kind != .remainder
    }

    var canReveal: Bool {
        url != nil && kind != .remainder
    }

    func descendant(for path: [String]) -> StorageNode {
        var current = self

        for id in path {
            guard let child = current.children.first(where: { $0.id == id }) else {
                break
            }
            current = child
        }

        return current
    }

    func breadcrumb(for path: [String]) -> [StorageNode] {
        var nodes: [StorageNode] = [self]
        var current = self

        for id in path {
            guard let child = current.children.first(where: { $0.id == id }) else {
                break
            }
            nodes.append(child)
            current = child
        }

        return nodes
    }
}

struct StorageReport: Hashable {
    let sections: [StorageSection]
    let largeFiles: [LargeFileEntry]
    let explorerRoot: StorageNode
    let volumes: [StorageVolume]
    let hiddenInsights: [StorageInsight]
    let adminInsights: [StorageInsight]
    let hiddenVolumes: [StorageVolume]

    var totalTrackedBytes: UInt64 {
        sections.reduce(into: 0) { $0 += $1.sizeBytes }
    }
}
