import Foundation

enum GuardPurpose {
    case cleanup
    case uninstall
    case analyze
    case storage
    case developerTooling
    case quarantine
}

actor SystemGuard {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    private lazy var cleanupRoots: [URL] = [
        home.appendingPathComponent("Library/Caches"),
        home.appendingPathComponent("Library/Logs"),
        home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
        home.appendingPathComponent("Library/Developer/CoreSimulator/Caches"),
        home.appendingPathComponent("Downloads"),
        home.appendingPathComponent("Desktop"),
        home.appendingPathComponent("Documents"),
        home.appendingPathComponent("Library/Caches/Google/Chrome"),
        home.appendingPathComponent("Library/Caches/BraveSoftware/Brave-Browser"),
        home.appendingPathComponent("Library/Caches/Microsoft Edge"),
        home.appendingPathComponent("Library/Caches/Firefox"),
        home.appendingPathComponent(".Trash"),
        home.appendingPathComponent(".npm/_cacache"),
        home.appendingPathComponent(".gradle/caches"),
        home.appendingPathComponent(".pnpm-store"),
        home.appendingPathComponent(".cache/yarn")
    ]

    private lazy var uninstallRoots: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        home.appendingPathComponent("Applications"),
        home.appendingPathComponent("Library/Application Support"),
        home.appendingPathComponent("Library/Caches"),
        home.appendingPathComponent("Library/Preferences"),
        home.appendingPathComponent("Library/Logs"),
        home.appendingPathComponent("Library/Saved Application State"),
        home.appendingPathComponent("Library/Containers"),
        home.appendingPathComponent("Library/WebKit"),
        home.appendingPathComponent("Library/LaunchAgents"),
        home.appendingPathComponent(".Trash")
    ]

    private lazy var developerToolRoots: [URL] = [
        URL(fileURLWithPath: "/usr/local/lib"),
        URL(fileURLWithPath: "/opt/homebrew/lib"),
        home.appendingPathComponent("lib")
    ]

    private lazy var quarantineRoots: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        home.appendingPathComponent("Applications"),
        home.appendingPathComponent("Downloads"),
        home.appendingPathComponent("Desktop"),
        home.appendingPathComponent("Documents")
    ]

    private let protectedRoots: [String] = [
        "/System",
        "/bin",
        "/sbin",
        "/usr",
        "/private/var/db",
        "/private/var/root",
        "/System/Volumes",
        "/Library/Apple"
    ]

    func canOperate(on url: URL, purpose: GuardPurpose) -> Bool {
        let normalized = URLPathSafety.standardized(url)
        let path = normalized.path

        if purpose != .analyze,
           purpose != .developerTooling,
           protectedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return false
        }

        switch purpose {
        case .cleanup:
            return cleanupRoots.contains(where: { URLPathSafety.isDescendant(normalized, of: $0) })
        case .uninstall:
            if path.hasPrefix("/System/Applications") {
                return false
            }
            return uninstallRoots.contains(where: { URLPathSafety.isDescendant(normalized, of: $0) })
        case .analyze:
            return FileManager.default.fileExists(atPath: path) && FileManager.default.isReadableFile(atPath: path)
        case .storage:
            let homeApplications = home.appendingPathComponent("Applications")
            let components = normalized.pathComponents

            guard URLPathSafety.isDescendant(normalized, of: home) else {
                return false
            }

            if URLPathSafety.isDescendant(normalized, of: homeApplications) {
                return false
            }

            if normalized.pathExtension.lowercased() == "app" {
                return false
            }

            return !components.dropLast().contains(where: { $0.lowercased().hasSuffix(".app") })
        case .developerTooling:
            guard normalized.pathExtension.lowercased() == "dylib" else {
                return false
            }

            return developerToolRoots.contains(where: { URLPathSafety.isDescendant(normalized, of: $0) })
        case .quarantine:
            guard normalized.pathExtension.lowercased() == "app" else {
                return false
            }

            return quarantineRoots.contains(where: { URLPathSafety.isDescendant(normalized, of: $0) })
        }
    }

    func isProtectedApplication(_ url: URL, bundleIdentifier: String?) -> Bool {
        let normalized = URLPathSafety.standardized(url).path
        return normalized.hasPrefix("/System/Applications") || (bundleIdentifier?.hasPrefix("com.apple.") ?? false)
    }

    func moveToTrash(_ url: URL, purpose: GuardPurpose) async throws {
        guard canOperate(on: url, purpose: purpose) else {
            throw NSError(
                domain: "SKMole.SystemGuard",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Blocked action for protected or unsupported path: \(url.path)"]
            )
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        try await MainActor.run {
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
        }
    }

    func removePermanently(_ url: URL, purpose: GuardPurpose) throws {
        guard canOperate(on: url, purpose: purpose) else {
            throw NSError(
                domain: "SKMole.SystemGuard",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Blocked permanent removal for protected or unsupported path: \(url.path)"]
            )
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        try FileManager.default.removeItem(at: url)
    }
}
