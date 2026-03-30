import Foundation
import UniformTypeIdentifiers

enum MaintenanceExportPluginID: String, CaseIterable, Identifiable, Hashable {
    case dryRunJSON
    case overviewMarkdown
    case overviewText
    case focusedStorageJSON
    case networkSnapshotJSON

    var id: String { rawValue }
}

struct MaintenanceExportPluginDescriptor: Identifiable, Hashable {
    let id: MaintenanceExportPluginID
    let title: String
    let subtitle: String
    let icon: String
    let fileExtension: String
    let contentType: UTType

    var suggestedBaseName: String {
        switch id {
        case .dryRunJSON:
            return "SK-Mole-Dry-Run"
        case .overviewMarkdown:
            return "SK-Mole-Overview"
        case .overviewText:
            return "SK-Mole-Overview"
        case .focusedStorageJSON:
            return "SK-Mole-Storage-Focus"
        case .networkSnapshotJSON:
            return "SK-Mole-Network-Snapshot"
        }
    }
}

struct MaintenanceExportContext {
    let maintenanceReport: MaintenanceReport
    let focusedStorageNode: StorageNode?
    let storageFocusConfiguration: StorageFocusConfiguration
    let networkReport: NetworkInspectorReport?
    let metrics: SystemMetricSnapshot
}

struct MaintenanceExportDocument {
    let descriptor: MaintenanceExportPluginDescriptor
    let data: Data
}
