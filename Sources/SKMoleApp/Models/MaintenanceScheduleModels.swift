import Foundation

enum ScheduledMaintenanceInterval: String, CaseIterable, Hashable, Identifiable {
    case off
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }

    var minimumSpacing: TimeInterval? {
        switch self {
        case .off:
            return nil
        case .daily:
            return 60 * 60 * 24
        case .weekly:
            return 60 * 60 * 24 * 7
        }
    }
}

enum ScheduledMaintenanceExportFormat: String, CaseIterable, Hashable, Identifiable {
    case markdown
    case json
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown: "Markdown"
        case .json: "JSON"
        case .text: "Text"
        }
    }

    var pluginID: MaintenanceExportPluginID {
        switch self {
        case .markdown:
            return .overviewMarkdown
        case .json:
            return .dryRunJSON
        case .text:
            return .overviewText
        }
    }
}
