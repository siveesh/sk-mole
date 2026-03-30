import Foundation

struct OptimizeActionDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let executable: String
    let arguments: [String]
    let caution: String
}

struct OptimizationLog: Identifiable, Hashable {
    let id = UUID()
    let actionTitle: String
    let output: String
    let succeeded: Bool
    let timestamp: Date
}

struct MaintenanceQuickAction: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
}

struct MaintenanceReport: Codable, Identifiable, Hashable {
    let id = UUID()
    let createdAt: Date
    let score: Int
    let fullDiskAccessStatus: String
    let cleanupBytes: UInt64
    let cleanupCategories: [String]
    let topRecommendations: [String]
    let storageSummary: [String]
    let storageFocusSummary: [String]
    let networkSummary: [String]
    let trashedApps: [String]
    let menuBarAlerts: [String]

    enum CodingKeys: String, CodingKey {
        case createdAt
        case score
        case fullDiskAccessStatus
        case cleanupBytes
        case cleanupCategories
        case topRecommendations
        case storageSummary
        case storageFocusSummary
        case networkSummary
        case trashedApps
        case menuBarAlerts
    }
}
