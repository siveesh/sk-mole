import Foundation
import SKMoleShared

enum AppUpdateItemKind: String, Hashable, Identifiable {
    case application
    case package

    var id: String { rawValue }

    var title: String {
        switch self {
        case .application: "Application"
        case .package: "Package"
        }
    }
}

enum AppUpdateSourceKind: String, Hashable, Identifiable {
    case homebrew
    case appStore
    case sparkle
    case github
    case vendor
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .homebrew: "Homebrew"
        case .appStore: "App Store"
        case .sparkle: "Sparkle"
        case .github: "GitHub"
        case .vendor: "Vendor Site"
        case .unknown: "Untracked"
        }
    }

    var symbol: String {
        switch self {
        case .homebrew: "cup.and.saucer.fill"
        case .appStore: "storefront"
        case .sparkle: "sparkles"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .vendor: "globe"
        case .unknown: "questionmark.app"
        }
    }
}

enum AppUpdateStatusKind: String, Hashable {
    case updateAvailable
    case upToDate
    case manualCheck
    case unsupported
    case error

    var title: String {
        switch self {
        case .updateAvailable: "Update Available"
        case .upToDate: "Up to Date"
        case .manualCheck: "Manual Review"
        case .unsupported: "No Structured Source"
        case .error: "Check Failed"
        }
    }
}

enum AppUpdateListFilter: String, CaseIterable, Identifiable {
    case attention
    case automatic
    case manual
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attention: "Needs Attention"
        case .automatic: "Automatic"
        case .manual: "Manual"
        case .all: "All"
        }
    }
}

enum AppUpdateCheckInterval: String, CaseIterable, Identifiable {
    case off
    case everySixHours
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .everySixHours: "Every 6 Hours"
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }

    var minimumSpacing: TimeInterval? {
        switch self {
        case .off:
            return nil
        case .everySixHours:
            return 6 * 60 * 60
        case .daily:
            return 24 * 60 * 60
        case .weekly:
            return 7 * 24 * 60 * 60
        }
    }
}

struct AppStoreAutomationStatus: Hashable {
    static let installCommand = "brew install mas"
    static let installGuideURL = URL(string: "https://github.com/mas-cli/mas")!

    let executablePath: String?
    let version: String?
    let accountName: String?
    let accountDetail: String?

    var isInstalled: Bool {
        executablePath != nil
    }

    var isSignedIn: Bool {
        accountName != nil
    }

    var canInstallUpdates: Bool {
        isInstalled && isSignedIn
    }

    var summary: String {
        if let accountName {
            if let version {
                return "mas \(version) signed in as \(accountName)"
            }

            return "mas signed in as \(accountName)"
        }

        if isInstalled {
            return "mas installed, but no App Store account detected"
        }

        return "mas not installed"
    }

    var detail: String {
        if let accountDetail, !accountDetail.isEmpty {
            return accountDetail
        }

        if isInstalled {
            return "Install automation is available once `mas` can access an App Store account on this Mac."
        }

        return "Install `mas` to let SK Mole upgrade Mac App Store apps from the command line when an update is available."
    }
}

struct AppUpdateItem: Identifiable, Hashable {
    let id: String
    let kind: AppUpdateItemKind
    let displayName: String
    let bundleIdentifier: String?
    let installedVersion: String?
    let latestVersion: String?
    let sourceKind: AppUpdateSourceKind
    let status: AppUpdateStatusKind
    let detail: String
    let sourceDescription: String
    let appURL: URL?
    let homepageURL: URL?
    let primaryURL: URL?
    let primaryURLTitle: String?
    let secondaryURL: URL?
    let secondaryURLTitle: String?
    let homebrewReference: HomebrewPackageReference?
    let appStoreAdamID: Int?
    let commandPreview: String?
    let canAutoInstall: Bool
    let releaseNotesSummary: String?
    let releaseNotesURL: URL?
    let releaseNotesURLTitle: String?
    let fullReleaseNotesURL: URL?
    let fullReleaseNotesURLTitle: String?
    let publishedAt: Date?

    var versionSummary: String {
        let installed = installedVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let latest = latestVersion?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (installed, latest) {
        case let (.some(installed), .some(latest)) where !installed.isEmpty && !latest.isEmpty:
            if installed == latest {
                return installed
            }
            return "\(installed) -> \(latest)"
        case let (.some(installed), _):
            return installed.isEmpty ? "Version unavailable" : installed
        case let (_, .some(latest)):
            return latest.isEmpty ? "Version unavailable" : "Latest \(latest)"
        default:
            return "Version unavailable"
        }
    }

    var searchableText: String {
        [
            displayName,
            bundleIdentifier,
            installedVersion,
            latestVersion,
            sourceKind.title,
            detail,
            sourceDescription,
            releaseNotesSummary,
            appURL?.path,
            homepageURL?.absoluteString
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    var normalizedLatestVersion: String? {
        AppUpdateService.normalizedVersion(latestVersion)
    }

    var releaseNotesPreview: String? {
        guard let releaseNotesSummary else {
            return nil
        }

        let collapsed = releaseNotesSummary
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !collapsed.isEmpty else {
            return nil
        }

        if collapsed.count <= 220 {
            return collapsed
        }

        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: 220)
        return String(collapsed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}

struct AppUpdateReport: Hashable {
    let scannedAt: Date
    let appStoreAutomation: AppStoreAutomationStatus
    let scannedApplicationCount: Int
    let scannedPackageCount: Int
    let items: [AppUpdateItem]

    var availableItems: [AppUpdateItem] {
        items.filter { $0.status == .updateAvailable }
    }

    var automaticItems: [AppUpdateItem] {
        availableItems.filter(\.canAutoInstall)
    }

    var manualItems: [AppUpdateItem] {
        items.filter { item in
            switch item.status {
            case .updateAvailable:
                return !item.canAutoInstall
            case .manualCheck, .error:
                return true
            case .upToDate, .unsupported:
                return false
            }
        }
    }

    var unsupportedItems: [AppUpdateItem] {
        items.filter { $0.status == .unsupported }
    }

    var upToDateItems: [AppUpdateItem] {
        items.filter { $0.status == .upToDate }
    }
}
