import Foundation

enum SafetyLevel: String, CaseIterable, Hashable {
    case safe
    case review
    case protected

    var title: String {
        switch self {
        case .safe: "Safe"
        case .review: "Review"
        case .protected: "Protected"
        }
    }
}

enum CleanupCategoryID: String, CaseIterable, Identifiable, Hashable {
    case userCaches
    case browserLeftovers
    case logs
    case developer
    case packageManagers
    case installers
    case oldDownloads
    case duplicates
    case trash

    var id: String { rawValue }
}

struct CleanupCandidate: Identifiable, Hashable {
    let url: URL
    let displayName: String
    let sizeBytes: UInt64
    let lastModified: Date?
    let rationale: String
    let safetyLevel: SafetyLevel

    var id: String { url.path }
}

struct CleanupCategorySummary: Identifiable, Hashable {
    let category: CleanupCategoryID
    let title: String
    let subtitle: String
    let icon: String
    let safetyLevel: SafetyLevel
    let totalBytes: UInt64
    let candidates: [CleanupCandidate]

    var id: CleanupCategoryID { category }
}
