import Foundation
import Testing
@testable import SKMoleApp

@Test func storageFocusCollapsesCommonClutter() async throws {
    let transformer = StorageFocusTransformer()
    let root = StorageNode(
        id: "root",
        name: "Root",
        icon: "internaldrive",
        url: URL(fileURLWithPath: "/"),
        sizeBytes: 12 * 1_024 * 1_024 * 1_024,
        kind: .root,
        children: [
            StorageNode(
                id: "photos",
                name: "Photos",
                icon: "photo",
                url: URL(fileURLWithPath: "/Photos"),
                sizeBytes: 6 * 1_024 * 1_024 * 1_024,
                kind: .directory,
                children: []
            ),
            StorageNode(
                id: "node-modules",
                name: "node_modules",
                icon: "shippingbox",
                url: URL(fileURLWithPath: "/node_modules"),
                sizeBytes: 3 * 1_024 * 1_024 * 1_024,
                kind: .directory,
                children: []
            ),
            StorageNode(
                id: "derived-data",
                name: "DerivedData",
                icon: "hammer.fill",
                url: URL(fileURLWithPath: "/DerivedData"),
                sizeBytes: 2 * 1_024 * 1_024 * 1_024,
                kind: .directory,
                children: []
            )
        ]
    )

    let result = transformer.transform(
        node: root,
        configuration: StorageFocusConfiguration(
            mode: .balanced,
            minimumSize: .all,
            collapseCommonClutter: true
        )
    )

    let names = Set(result.node.children.map(\.name))
    #expect(names.contains("Photos"))
    #expect(names.contains("Dependency Stores"))
    #expect(names.contains("Build Artifacts"))
    #expect(!names.contains("node_modules"))
    #expect(!names.contains("DerivedData"))
}

@Test func storageFocusGroupsLeafFilesByType() async throws {
    let transformer = StorageFocusTransformer()
    let root = StorageNode(
        id: "root",
        name: "Root",
        icon: "internaldrive",
        url: URL(fileURLWithPath: "/"),
        sizeBytes: 6 * 1_024 * 1_024 * 1_024,
        kind: .root,
        children: [
            StorageNode(
                id: "photo-one",
                name: "Photo One",
                icon: "photo",
                url: URL(fileURLWithPath: "/photo-one.jpg"),
                sizeBytes: 2 * 1_024 * 1_024 * 1_024,
                kind: .file,
                children: []
            ),
            StorageNode(
                id: "photo-two",
                name: "Photo Two",
                icon: "photo",
                url: URL(fileURLWithPath: "/photo-two.png"),
                sizeBytes: 1 * 1_024 * 1_024 * 1_024,
                kind: .file,
                children: []
            ),
            StorageNode(
                id: "archive",
                name: "Archive",
                icon: "archivebox",
                url: URL(fileURLWithPath: "/archive.zip"),
                sizeBytes: 3 * 1_024 * 1_024 * 1_024,
                kind: .file,
                children: []
            )
        ]
    )

    let result = transformer.transform(
        node: root,
        configuration: StorageFocusConfiguration(
            mode: .fileTypes,
            minimumSize: .all,
            collapseCommonClutter: false
        )
    )

    let groupedNames = Set(result.node.children.map(\.name))
    #expect(groupedNames.contains("Images"))
    #expect(groupedNames.contains("Archives"))
}

@Test func exportRegistrySurfacesConditionalPlugins() async throws {
    let registry = MaintenanceExportRegistry()
    let maintenanceReport = MaintenanceReport(
        createdAt: .now,
        score: 92,
        fullDiskAccessStatus: "Granted",
        cleanupBytes: 1_024,
        cleanupCategories: [],
        topRecommendations: [],
        storageSummary: [],
        storageFocusSummary: [],
        networkSummary: [],
        trashedApps: [],
        menuBarAlerts: []
    )

    let baseContext = MaintenanceExportContext(
        maintenanceReport: maintenanceReport,
        focusedStorageNode: nil,
        storageFocusConfiguration: StorageFocusConfiguration(),
        networkReport: nil,
        metrics: .placeholder
    )
    let basePlugins = Set(registry.availablePlugins(for: baseContext).map(\.id))

    #expect(basePlugins.contains(.dryRunJSON))
    #expect(!basePlugins.contains(.focusedStorageJSON))
    #expect(!basePlugins.contains(.networkSnapshotJSON))

    let storageNode = StorageNode(
        id: "root",
        name: "Root",
        icon: "internaldrive",
        url: URL(fileURLWithPath: "/"),
        sizeBytes: 1_024,
        kind: .root,
        children: []
    )
    let networkReport = NetworkInspectorReport(
        capturedAt: .now,
        resolvesHostnames: false,
        includesListeningSockets: true,
        interfaces: [],
        processes: [],
        connections: [],
        remoteHosts: []
    )
    let fullContext = MaintenanceExportContext(
        maintenanceReport: maintenanceReport,
        focusedStorageNode: storageNode,
        storageFocusConfiguration: StorageFocusConfiguration(),
        networkReport: networkReport,
        metrics: .placeholder
    )
    let fullPlugins = Set(registry.availablePlugins(for: fullContext).map(\.id))

    #expect(fullPlugins.contains(.focusedStorageJSON))
    #expect(fullPlugins.contains(.networkSnapshotJSON))
}
