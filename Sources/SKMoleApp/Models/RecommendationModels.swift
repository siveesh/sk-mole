import Foundation
import SKMoleShared

enum RecommendedActionPriority: String, CaseIterable, Hashable {
    case urgent
    case recommended
    case optional

    var title: String {
        switch self {
        case .urgent: "Urgent"
        case .recommended: "Recommended"
        case .optional: "Optional"
        }
    }

    var symbol: String {
        switch self {
        case .urgent: "exclamationmark.triangle.fill"
        case .recommended: "sparkles"
        case .optional: "checkmark.circle"
        }
    }
}

enum RecommendedActionIntent: Hashable {
    case openSection(SidebarSection)
    case trashCleanupCategory(CleanupCategoryID)
    case previewApplication(String)
    case previewTrashedApplication(String)
    case resetApplication(String)
    case focusVolume(String)
    case setStorageMode(StorageInspectionMode)
    case revealURL(URL)
    case openFullDiskAccess
    case exportDryRunReport
    case runPrivilegedTask(PrivilegedMaintenanceTask)
}

struct RecommendedAction: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let detail: String
    let icon: String
    let priority: RecommendedActionPriority
    let estimatedImpactBytes: UInt64?
    let callToAction: String
    let intent: RecommendedActionIntent

    init(
        id: String,
        title: String,
        subtitle: String,
        detail: String,
        icon: String,
        priority: RecommendedActionPriority,
        estimatedImpactBytes: UInt64? = nil,
        callToAction: String,
        intent: RecommendedActionIntent
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.icon = icon
        self.priority = priority
        self.estimatedImpactBytes = estimatedImpactBytes
        self.callToAction = callToAction
        self.intent = intent
    }
}
