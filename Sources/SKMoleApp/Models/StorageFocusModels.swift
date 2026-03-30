import Foundation

enum StorageFocusMode: String, CaseIterable, Identifiable, Hashable {
    case balanced
    case directories
    case files
    case fileTypes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .directories: "Folders"
        case .files: "Files"
        case .fileTypes: "File Types"
        }
    }

    var subtitle: String {
        switch self {
        case .balanced: "Largest visible folders and bundles"
        case .directories: "Directory-first view with noisy churn collapsed"
        case .files: "Leaf files and app bundles from the visible subtree"
        case .fileTypes: "Aggregate bytes by broad file type"
        }
    }

    var isSummaryMode: Bool {
        self == .fileTypes
    }
}

enum StorageMinimumSizeFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case medium
    case large
    case huge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Sizes"
        case .medium: "256 MB+"
        case .large: "1 GB+"
        case .huge: "4 GB+"
        }
    }

    var minimumBytes: UInt64 {
        switch self {
        case .all: 0
        case .medium: 256 * 1_024 * 1_024
        case .large: 1 * 1_024 * 1_024 * 1_024
        case .huge: 4 * 1_024 * 1_024 * 1_024
        }
    }
}

struct StorageFocusConfiguration: Hashable {
    var mode: StorageFocusMode = .balanced
    var minimumSize: StorageMinimumSizeFilter = .all
    var collapseCommonClutter = true
}

struct StorageFocusResult: Hashable {
    let node: StorageNode
    let sourceChildCount: Int
    let visibleChildCount: Int
    let hiddenChildCount: Int
    let mode: StorageFocusMode
    let minimumSize: StorageMinimumSizeFilter
    let collapseCommonClutter: Bool

    var summaryLine: String {
        var parts: [String] = [mode.subtitle]
        parts.append("\(visibleChildCount) visible item\(visibleChildCount == 1 ? "" : "s")")

        if hiddenChildCount > 0 {
            parts.append("\(hiddenChildCount) filtered")
        }

        if collapseCommonClutter {
            parts.append("common clutter collapsed")
        }

        return parts.joined(separator: " • ")
    }
}
