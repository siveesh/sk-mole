import Foundation

struct MagikaStatus: Hashable {
    static let homepageURL = URL(string: "https://securityresearch.google/magika/")!
    static let repositoryURL = URL(string: "https://github.com/google/magika")!
    static let installCommand = "brew install magika"
    static let pipxInstallCommand = "pipx install magika"
    static let homebrewReference = HomebrewPackageReference(token: "magika", kind: .formula)

    let executablePath: String?
    let version: String?

    var isInstalled: Bool {
        executablePath != nil
    }

    var summary: String {
        guard isInstalled else {
            return "Magika not installed"
        }

        if let version {
            return "Magika \(version)"
        }

        return "Magika installed"
    }

    var detail: String {
        guard isInstalled else {
            return "Install Magika once and SK Mole can identify files by content, scan folders recursively, surface confidence fallbacks, and flag extension mismatches."
        }

        return "SK Mole can now use Magika's trusted output, raw model guess, MIME details, and recursive directory scans through a native file-intelligence workflow."
    }
}

struct MagikaScanTarget: Hashable, Identifiable {
    enum Kind: String, Hashable {
        case file
        case directory

        var title: String {
            switch self {
            case .file:
                return "File"
            case .directory:
                return "Folder"
            }
        }

        var symbol: String {
            switch self {
            case .file:
                return "doc"
            case .directory:
                return "folder"
            }
        }
    }

    let url: URL
    let kind: Kind

    var id: String { url.path }

    var displayName: String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }
}

struct MagikaContentTypeInfo: Decodable, Hashable {
    let description: String
    let extensions: [String]
    let group: String
    let isText: Bool
    let label: String
    let mimeType: String

    enum CodingKeys: String, CodingKey {
        case description
        case extensions
        case group
        case isText = "is_text"
        case label
        case mimeType = "mime_type"
    }
}

struct MagikaScanItem: Hashable, Identifiable {
    let path: URL
    let status: String
    let trustedType: MagikaContentTypeInfo?
    let modelType: MagikaContentTypeInfo?
    let score: Double?
    let overwriteReason: String?
    let detail: String?
    let fileSizeBytes: UInt64?

    var id: String { path.path }

    var displayName: String {
        let name = path.lastPathComponent
        return name.isEmpty ? path.path : name
    }

    var parentDirectory: String {
        path.deletingLastPathComponent().path
    }

    var effectiveType: MagikaContentTypeInfo? {
        trustedType ?? modelType
    }

    var group: String {
        effectiveType?.group ?? "unknown"
    }

    var mimeType: String {
        effectiveType?.mimeType ?? "Unknown"
    }

    var confidencePercent: String {
        guard let score else {
            return "—"
        }

        return String(format: "%.1f%%", score * 100)
    }

    var actualExtension: String? {
        let ext = path.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ext.isEmpty ? nil : ext
    }

    var expectedExtensions: [String] {
        effectiveType?.extensions ?? []
    }

    var extensionMismatch: Bool {
        guard let actualExtension, !expectedExtensions.isEmpty else {
            return false
        }

        let normalizedExpected = Set(expectedExtensions.map { $0.lowercased() })
        return !normalizedExpected.contains(actualExtension)
    }

    var usesConfidenceFallback: Bool {
        guard let trustedType, let modelType else {
            return false
        }

        return trustedType.label != modelType.label
            || trustedType.mimeType != modelType.mimeType
    }

    var isInteresting: Bool {
        status != "ok" || usesConfidenceFallback || extensionMismatch
    }

    var isText: Bool? {
        effectiveType?.isText
    }

    var overwriteSummary: String? {
        if let overwriteReason, !overwriteReason.isEmpty {
            return overwriteReason
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }

        guard usesConfidenceFallback,
              let trustedType,
              let modelType else {
            return nil
        }

        return "Model guessed \(modelType.description), but Magika returned \(trustedType.description) after confidence checks."
    }
}

struct MagikaGroupSummary: Hashable, Identifiable {
    let group: String
    let count: Int
    let totalBytes: UInt64

    var id: String { group }

    var title: String {
        group.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct MagikaScanReport: Hashable {
    let status: MagikaStatus
    let targets: [MagikaScanTarget]
    let recursive: Bool
    let command: String
    let items: [MagikaScanItem]
    let scannedAt: Date

    var scannedCount: Int {
        items.count
    }

    var okCount: Int {
        items.filter { $0.status == "ok" }.count
    }

    var confidenceFallbackCount: Int {
        items.filter(\.usesConfidenceFallback).count
    }

    var extensionMismatchCount: Int {
        items.filter(\.extensionMismatch).count
    }

    var interestingCount: Int {
        items.filter(\.isInteresting).count
    }

    var totalBytes: UInt64 {
        items.reduce(into: 0) { partialResult, item in
            partialResult += item.fileSizeBytes ?? 0
        }
    }

    var groupSummaries: [MagikaGroupSummary] {
        Dictionary(grouping: items.filter { $0.status == "ok" }, by: \.group)
            .map { group, matches in
                MagikaGroupSummary(
                    group: group,
                    count: matches.count,
                    totalBytes: matches.reduce(into: 0) { $0 += $1.fileSizeBytes ?? 0 }
                )
            }
            .sorted { left, right in
                if left.count != right.count {
                    return left.count > right.count
                }

                return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
            }
    }
}
