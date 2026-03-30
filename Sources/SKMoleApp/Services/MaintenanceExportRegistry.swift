import Foundation

final class MaintenanceExportRegistry {
    private struct CodableStorageNode: Codable {
        let name: String
        let icon: String
        let path: String?
        let sizeBytes: UInt64
        let kind: String
        let children: [CodableStorageNode]

        init(node: StorageNode) {
            self.name = node.name
            self.icon = node.icon
            self.path = node.url?.path
            self.sizeBytes = node.sizeBytes
            self.kind = node.kind.rawValue
            self.children = node.children.map(CodableStorageNode.init(node:))
        }
    }

    private struct StorageExportEnvelope: Codable {
        let generatedAt: Date
        let focusMode: String
        let minimumSize: String
        let collapseCommonClutter: Bool
        let root: CodableStorageNode
    }

    func availablePlugins(for context: MaintenanceExportContext) -> [MaintenanceExportPluginDescriptor] {
        var plugins: [MaintenanceExportPluginDescriptor] = [
            descriptor(for: .dryRunJSON),
            descriptor(for: .overviewMarkdown),
            descriptor(for: .overviewText)
        ]

        if context.focusedStorageNode != nil {
            plugins.append(descriptor(for: .focusedStorageJSON))
        }

        if context.networkReport != nil {
            plugins.append(descriptor(for: .networkSnapshotJSON))
        }

        return plugins
    }

    func export(plugin id: MaintenanceExportPluginID, context: MaintenanceExportContext) throws -> MaintenanceExportDocument {
        let descriptor = descriptor(for: id)

        switch id {
        case .dryRunJSON:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return MaintenanceExportDocument(
                descriptor: descriptor,
                data: try encoder.encode(context.maintenanceReport)
            )
        case .overviewMarkdown:
            return MaintenanceExportDocument(
                descriptor: descriptor,
                data: Data(markdown(from: context).utf8)
            )
        case .overviewText:
            return MaintenanceExportDocument(
                descriptor: descriptor,
                data: Data(textOverview(from: context).utf8)
            )
        case .focusedStorageJSON:
            guard let focusedStorageNode = context.focusedStorageNode else {
                throw NSError(
                    domain: "SKMole.Export",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "No focused storage tree is available to export yet."]
                )
            }

            let payload = StorageExportEnvelope(
                generatedAt: context.maintenanceReport.createdAt,
                focusMode: context.storageFocusConfiguration.mode.title,
                minimumSize: context.storageFocusConfiguration.minimumSize.title,
                collapseCommonClutter: context.storageFocusConfiguration.collapseCommonClutter,
                root: CodableStorageNode(node: focusedStorageNode)
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return MaintenanceExportDocument(descriptor: descriptor, data: try encoder.encode(payload))
        case .networkSnapshotJSON:
            guard let networkReport = context.networkReport else {
                throw NSError(
                    domain: "SKMole.Export",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "No network snapshot is available yet. Open the Network section and refresh it first."]
                )
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return MaintenanceExportDocument(descriptor: descriptor, data: try encoder.encode(networkReport))
        }
    }

    func descriptor(for id: MaintenanceExportPluginID) -> MaintenanceExportPluginDescriptor {
        switch id {
        case .dryRunJSON:
            return MaintenanceExportPluginDescriptor(
                id: id,
                title: "Dry Run JSON",
                subtitle: "Machine-readable maintenance snapshot with cleanup, storage, Smart Care, and alert context.",
                icon: "curlybraces",
                fileExtension: "json",
                contentType: .json
            )
        case .overviewMarkdown:
            return MaintenanceExportPluginDescriptor(
                id: id,
                title: "Overview Markdown",
                subtitle: "Readable status summary you can drop into notes, tickets, or release docs.",
                icon: "doc.richtext",
                fileExtension: "md",
                contentType: .plainText
            )
        case .overviewText:
            return MaintenanceExportPluginDescriptor(
                id: id,
                title: "Overview Text",
                subtitle: "Plain-text snapshot for quick sharing or archival without JSON noise.",
                icon: "doc.plaintext",
                fileExtension: "txt",
                contentType: .plainText
            )
        case .focusedStorageJSON:
            return MaintenanceExportPluginDescriptor(
                id: id,
                title: "Focused Storage Tree",
                subtitle: "Exports the current Dust-style storage lens exactly as you’re viewing it.",
                icon: "square.grid.3x3.square",
                fileExtension: "json",
                contentType: .json
            )
        case .networkSnapshotJSON:
            return MaintenanceExportPluginDescriptor(
                id: id,
                title: "Network Snapshot",
                subtitle: "Current process, connection, remote-host, and interface snapshot from the on-demand network inspector.",
                icon: "network",
                fileExtension: "json",
                contentType: .json
            )
        }
    }

    private func markdown(from context: MaintenanceExportContext) -> String {
        var lines: [String] = [
            "# SK Mole Overview",
            "",
            "- Generated: \(ISO8601DateFormatter().string(from: context.maintenanceReport.createdAt))",
            "- Smart Care score: \(context.maintenanceReport.score)",
            "- Full Disk Access: \(context.maintenanceReport.fullDiskAccessStatus)",
            "- Cleanup estimate: \(ByteFormatting.format(context.maintenanceReport.cleanupBytes))",
            ""
        ]

        if !context.maintenanceReport.topRecommendations.isEmpty {
            lines.append("## Recommendations")
            lines.append(contentsOf: context.maintenanceReport.topRecommendations.map { "- \($0)" })
            lines.append("")
        }

        if !context.maintenanceReport.storageSummary.isEmpty {
            lines.append("## Storage")
            lines.append(contentsOf: context.maintenanceReport.storageSummary.map { "- \($0)" })
            lines.append("")
        }

        if !context.maintenanceReport.networkSummary.isEmpty {
            lines.append("## Network")
            lines.append(contentsOf: context.maintenanceReport.networkSummary.map { "- \($0)" })
            lines.append("")
        }

        lines.append("## Live Metrics")
        lines.append("- CPU: \(Int((context.metrics.cpuUsage * 100).rounded()))%")
        lines.append("- Memory: \(Int((context.metrics.memoryUsage * 100).rounded()))%")
        lines.append("- Disk: \(Int((context.metrics.diskUsage * 100).rounded()))%")
        lines.append("- Network down: \(ByteFormatting.formatRate(context.metrics.networkDownloadRate))")
        lines.append("- Network up: \(ByteFormatting.formatRate(context.metrics.networkUploadRate))")
        return lines.joined(separator: "\n")
    }

    private func textOverview(from context: MaintenanceExportContext) -> String {
        [
            "SK Mole Overview",
            "",
            "Smart Care score: \(context.maintenanceReport.score)",
            "Full Disk Access: \(context.maintenanceReport.fullDiskAccessStatus)",
            "Cleanup estimate: \(ByteFormatting.format(context.maintenanceReport.cleanupBytes))",
            "Top recommendations:",
            context.maintenanceReport.topRecommendations.isEmpty
                ? "  - None"
                : context.maintenanceReport.topRecommendations.map { "  - \($0)" }.joined(separator: "\n"),
            "Storage summary:",
            context.maintenanceReport.storageSummary.isEmpty
                ? "  - No storage snapshot"
                : context.maintenanceReport.storageSummary.map { "  - \($0)" }.joined(separator: "\n"),
            "Network summary:",
            context.maintenanceReport.networkSummary.isEmpty
                ? "  - No network snapshot"
                : context.maintenanceReport.networkSummary.map { "  - \($0)" }.joined(separator: "\n")
        ].joined(separator: "\n")
    }
}
