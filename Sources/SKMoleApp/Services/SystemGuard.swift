import Foundation
import SKMoleShared

enum GuardPurpose {
    case cleanup
    case uninstall
    case analyze
    case storage
    case developerTooling
    case quarantine
}

struct GuardedFileIdentity: Equatable, Sendable {
    let volumeIdentifier: String
    let fileIdentifier: String
}

actor SystemGuard {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    private lazy var cleanupRoots: [URL] = [
        home.appendingPathComponent("Library/Caches"),
        home.appendingPathComponent("Library/Containers"),
        home.appendingPathComponent("Library/Group Containers"),
        home.appendingPathComponent("Library/Logs"),
        home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
        home.appendingPathComponent("Library/Developer/CoreSimulator/Caches"),
        home.appendingPathComponent("Library/Caches/com.docker.docker"),
        home.appendingPathComponent("Library/Containers/com.docker.docker/Data/log"),
        home.appendingPathComponent("Library/Containers/com.docker.docker/Data/tmp"),
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
        home.appendingPathComponent("Library/Group Containers"),
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

    private lazy var sensitiveHomeRoots: [URL] = [
        home.appendingPathComponent(".ssh"),
        home.appendingPathComponent(".gnupg"),
        home.appendingPathComponent(".aws"),
        home.appendingPathComponent(".config"),
        home.appendingPathComponent("Library/Keychains"),
        home.appendingPathComponent("Library/Mail"),
        home.appendingPathComponent("Library/Messages"),
        home.appendingPathComponent("Library/Safari"),
        home.appendingPathComponent("Library/Mobile Documents"),
        home.appendingPathComponent("Pictures/Photos Library.photoslibrary")
    ]

    private let protectedDotComponents: Set<String> = [
        ".git",
        ".svn",
        ".hg",
        ".ssh",
        ".gnupg",
        ".aws"
    ]

    private let protectedDotFiles: Set<String> = [
        ".zshrc",
        ".bashrc",
        ".bash_profile",
        ".profile",
        ".gitconfig"
    ]

    func canOperate(on url: URL, purpose: GuardPurpose) -> Bool {
        let normalized = URLPathSafety.standardized(url)
        let path = normalized.path

        if purpose != .analyze,
           purpose != .developerTooling,
           protectedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return false
        }

        if hasSensitiveComponents(normalized) || isSensitiveHomePath(normalized) {
            return false
        }

        switch purpose {
        case .cleanup:
            guard cleanupRoots.contains(where: { URLPathSafety.isDescendant(normalized, of: $0) }) else {
                return false
            }

            return isSupportedCleanupPath(normalized)
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
            return isSupportedDeveloperToolingPath(normalized)
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

    func canTerminate(process: NativeProcessActivity) -> Bool {
        Self.canTerminateSnapshot(process)
    }

    nonisolated static func canTerminateSnapshot(_ process: NativeProcessActivity) -> Bool {
        guard process.pid > 1, process.pid != getpid() else {
            return false
        }

        guard process.ownerUserID == getuid() else {
            return false
        }

        let protectedNames = ["SK Mole", "SK Mole Companion", "Finder", "Dock", "System Settings", "Activity Monitor", "loginwindow"]
        if protectedNames.contains(where: { process.name.localizedCaseInsensitiveCompare($0) == .orderedSame }) {
            return false
        }

        let commandURL = URL(fileURLWithPath: process.command)
        let normalized = URLPathSafety.standardized(commandURL)
        let path = normalized.path

        let protectedRoots = [
            "/System",
            "/bin",
            "/sbin",
            "/usr",
            "/private/var/db",
            "/private/var/root",
            "/System/Volumes",
            "/Library/Apple"
        ]

        if protectedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return false
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        return path.hasPrefix("/Applications/")
            || URLPathSafety.isDescendant(normalized, of: home)
            || path.hasPrefix("/opt/homebrew/")
            || path.hasPrefix("/usr/local/")
    }

    func moveToTrash(_ url: URL, purpose: GuardPurpose) async throws {
        let normalized = URLPathSafety.standardized(url)

        guard canOperate(on: normalized, purpose: purpose) else {
            throw NSError(
                domain: "SKMole.SystemGuard",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Blocked action for protected or unsupported path: \(url.path)"]
            )
        }

        guard FileManager.default.fileExists(atPath: normalized.path) else {
            return
        }

        try validateDeletionTarget(normalized, purpose: purpose)
        let identity = try Self.fileIdentity(for: normalized)
        try Self.validateStableTarget(normalized, expectedIdentity: identity)

        SKMoleLog.guardrails.info("Moving item to Trash: \(normalized.lastPathComponent, privacy: .public)")

        try await MainActor.run {
            try Self.validateStableTarget(normalized, expectedIdentity: identity)
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: normalized, resultingItemURL: &trashedURL)
        }
    }

    func removePermanently(_ url: URL, purpose: GuardPurpose) throws {
        let normalized = URLPathSafety.standardized(url)

        guard canOperate(on: normalized, purpose: purpose) else {
            throw NSError(
                domain: "SKMole.SystemGuard",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Blocked permanent removal for protected or unsupported path: \(url.path)"]
            )
        }

        guard FileManager.default.fileExists(atPath: normalized.path) else {
            return
        }

        try validateDeletionTarget(normalized, purpose: purpose)
        let identity = try Self.fileIdentity(for: normalized)
        try Self.validateStableTarget(normalized, expectedIdentity: identity)

        SKMoleLog.guardrails.info("Removing item permanently: \(normalized.lastPathComponent, privacy: .public)")
        try Self.validateStableTarget(normalized, expectedIdentity: identity)
        try FileManager.default.removeItem(at: normalized)
    }

    func operationIdentity(for url: URL, purpose: GuardPurpose) throws -> GuardedFileIdentity {
        let normalized = URLPathSafety.standardized(url)

        guard canOperate(on: normalized, purpose: purpose) else {
            throw NSError(
                domain: "SKMole.SystemGuard",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Blocked action for protected or unsupported path."]
            )
        }

        guard FileManager.default.fileExists(atPath: normalized.path) else {
            throw NSError(
                domain: "SKMole.SystemGuard",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "The selected item no longer exists."]
            )
        }

        try validateDeletionTarget(normalized, purpose: purpose)
        return try Self.fileIdentity(for: normalized)
    }

    nonisolated func validateStableOperationTarget(_ url: URL, expectedIdentity: GuardedFileIdentity) throws {
        try Self.validateStableTarget(url, expectedIdentity: expectedIdentity)
    }

    private func validateDeletionTarget(_ url: URL, purpose: GuardPurpose) throws {
        let normalized = URLPathSafety.standardized(url)
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]
        let values = try normalized.resourceValues(forKeys: keys)

        if values.isSymbolicLink == true {
            throw NSError(
                domain: "SKMole.SystemGuard",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "SK Mole refuses to operate on symbolic links for \(purpose)."]
            )
        }

        guard !hasSensitiveComponents(normalized), !isSensitiveHomePath(normalized) else {
            throw NSError(
                domain: "SKMole.SystemGuard",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "SK Mole blocked a sensitive path while validating this action."]
            )
        }
    }

    private nonisolated static func fileIdentity(for url: URL) throws -> GuardedFileIdentity {
        let values = try url.resourceValues(forKeys: [.fileResourceIdentifierKey, .volumeIdentifierKey])
        return GuardedFileIdentity(
            volumeIdentifier: values.volumeIdentifier.map { String(describing: $0) } ?? "volume:unknown",
            fileIdentifier: values.fileResourceIdentifier.map { String(describing: $0) } ?? "file:unknown"
        )
    }

    private nonisolated static func validateStableTarget(_ url: URL, expectedIdentity: GuardedFileIdentity) throws {
        let currentIdentity = try fileIdentity(for: url)
        guard currentIdentity == expectedIdentity else {
            throw NSError(
                domain: "SKMole.SystemGuard",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "SK Mole stopped because the target changed during validation: \(url.path)"]
            )
        }
    }

    private func hasSensitiveComponents(_ url: URL) -> Bool {
        let components = url.pathComponents.map { $0.lowercased() }

        if components.contains(where: { protectedDotComponents.contains($0) }) {
            return true
        }

        guard let last = components.last else {
            return false
        }

        return protectedDotFiles.contains(last)
    }

    private func isSensitiveHomePath(_ url: URL) -> Bool {
        sensitiveHomeRoots.contains(where: { URLPathSafety.isDescendant(url, of: $0) })
    }

    private func isSupportedDeveloperToolingPath(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "dylib" else {
            return false
        }

        guard developerToolRoots.contains(where: { root in
            URLPathSafety.standardized(url.deletingLastPathComponent()).path == URLPathSafety.standardized(root).path
        }) else {
            return false
        }

        guard url.lastPathComponent.hasPrefix("lib") else {
            return false
        }

        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true
    }

    private func isSupportedCleanupPath(_ url: URL) -> Bool {
        let normalizedPath = url.path

        if normalizedPath.contains("/Library/Containers/") || normalizedPath.contains("/Library/Group Containers/") {
            return normalizedPath.contains("/Library/Caches/")
                || normalizedPath.contains("/Data/Library/Caches/")
                || normalizedPath.contains("/Library/Logs/")
                || normalizedPath.contains("/Data/Library/Logs/")
                || normalizedPath.contains("/tmp/")
        }

        return true
    }
}
