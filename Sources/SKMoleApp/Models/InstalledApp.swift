import Foundation

enum InstalledAppLocation: String, Hashable {
    case managed
    case trash

    var title: String {
        switch self {
        case .managed: "Installed"
        case .trash: "In Trash"
        }
    }
}

enum UninstallPreviewMode: Hashable {
    case removeAppAndRemnants
    case resetApp
    case removeLeftoversOnly

    var actionTitle: String {
        switch self {
        case .removeAppAndRemnants: "Move App + Remnants to Trash"
        case .resetApp: "Reset App Data"
        case .removeLeftoversOnly: "Remove Leftovers"
        }
    }
}

enum UninstallSensitivityLevel: String, CaseIterable, Hashable, Identifiable {
    case strict
    case enhanced
    case deep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strict: "Strict"
        case .enhanced: "Enhanced"
        case .deep: "Deep"
        }
    }

    var subtitle: String {
        switch self {
        case .strict:
            return "Only exact bundle-ID support files."
        case .enhanced:
            return "Exact files plus strong related matches."
        case .deep:
            return "Adds wider user-domain pattern matching."
        }
    }
}

struct InstalledApp: Identifiable, Hashable {
    let name: String
    let bundleIdentifier: String?
    let url: URL
    let sizeBytes: UInt64
    let isRunning: Bool
    let isProtected: Bool
    let location: InstalledAppLocation

    var id: String { url.path }
    var isInTrash: Bool { location == .trash }
}

enum AssociatedItemDisposition: Hashable {
    case removedWithAppBundle
    case reviewOnly

    var title: String {
        switch self {
        case .removedWithAppBundle: "Removed with app"
        case .reviewOnly: "Review separately"
        }
    }
}

struct AppRemnant: Identifiable, Hashable {
    let url: URL
    let displayName: String
    let sizeBytes: UInt64
    let rationale: String
    let safetyLevel: SafetyLevel

    var id: String { url.path }
}

struct AssociatedAppItem: Identifiable, Hashable {
    let url: URL
    let displayName: String
    let sizeBytes: UInt64
    let rationale: String
    let symbol: String
    let disposition: AssociatedItemDisposition

    var id: String { url.path }
}

struct UninstallPreview: Hashable {
    let app: InstalledApp
    let remnants: [AppRemnant]
    let associatedItems: [AssociatedAppItem]
    let mode: UninstallPreviewMode
    let sensitivity: UninstallSensitivityLevel

    var removableBytes: UInt64 {
        switch mode {
        case .removeAppAndRemnants:
            app.sizeBytes + remnants.reduce(into: 0) { $0 += $1.sizeBytes }
        case .resetApp, .removeLeftoversOnly:
            remnants.reduce(into: 0) { $0 += $1.sizeBytes }
        }
    }
}
