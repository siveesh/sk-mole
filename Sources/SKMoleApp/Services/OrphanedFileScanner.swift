import Foundation

actor OrphanedFileScanner {
    private struct RootSpec {
        let category: OrphanedFileCategory
        let root: URL
        let minimumSize: UInt64
    }

    private let guardService: SystemGuard
    private let sizer: DirectorySizer
    private let fileManager = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    init(guardService: SystemGuard, sizer: DirectorySizer) {
        self.guardService = guardService
        self.sizer = sizer
    }

    func scan(
        installedApps: [InstalledApp],
        progress: @escaping @Sendable (ScanProgress) async -> Void = { _ in }
    ) async -> [OrphanedFileCandidate] {
        let bundleIdentifiers = Set(installedApps.compactMap { $0.bundleIdentifier?.lowercased() })
        let appNameTokens = Set(installedApps.map { Self.normalizedAppNameToken(for: $0.name) }.filter { !$0.isEmpty })

        let specs = [
            RootSpec(category: .preferences, root: home.appendingPathComponent("Library/Preferences"), minimumSize: 8 * 1_024),
            RootSpec(category: .savedState, root: home.appendingPathComponent("Library/Saved Application State"), minimumSize: 32 * 1_024),
            RootSpec(category: .containers, root: home.appendingPathComponent("Library/Containers"), minimumSize: 1 * 1_024 * 1_024),
            RootSpec(category: .groupContainers, root: home.appendingPathComponent("Library/Group Containers"), minimumSize: 1 * 1_024 * 1_024),
            RootSpec(category: .launchAgents, root: home.appendingPathComponent("Library/LaunchAgents"), minimumSize: 1),
            RootSpec(category: .applicationSupport, root: home.appendingPathComponent("Library/Application Support"), minimumSize: 16 * 1_024 * 1_024),
            RootSpec(category: .caches, root: home.appendingPathComponent("Library/Caches"), minimumSize: 16 * 1_024 * 1_024),
            RootSpec(category: .logs, root: home.appendingPathComponent("Library/Logs"), minimumSize: 8 * 1_024 * 1_024)
        ]

        var results: [OrphanedFileCandidate] = []

        for (index, spec) in specs.enumerated() {
            if Task.isCancelled {
                return results
            }

            await progress(
                ScanProgress(
                    title: "Orphan review",
                    detail: "Reviewing \(spec.category.title.lowercased())",
                    completedUnits: index + 1,
                    totalUnits: specs.count
                )
            )

            guard fileManager.fileExists(atPath: spec.root.path) else {
                continue
            }

            let children = await sizer.children(of: spec.root)
            for child in children {
                if Task.isCancelled {
                    return results
                }

                guard await guardService.canOperate(on: child, purpose: .uninstall) else {
                    continue
                }

                guard let candidate = await makeCandidate(
                    at: child,
                    spec: spec,
                    bundleIdentifiers: bundleIdentifiers,
                    appNameTokens: appNameTokens
                ) else {
                    continue
                }

                results.append(candidate)
            }
        }

        return Dictionary(grouping: results, by: \.id)
            .compactMap { $0.value.first }
            .sorted { left, right in
                if left.sizeBytes != right.sizeBytes {
                    return left.sizeBytes > right.sizeBytes
                }

                return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
            }
    }

    private func makeCandidate(
        at url: URL,
        spec: RootSpec,
        bundleIdentifiers: Set<String>,
        appNameTokens: Set<String>
    ) async -> OrphanedFileCandidate? {
        guard let rawToken = Self.rawToken(for: url, category: spec.category) else {
            return nil
        }

        let matchToken = Self.matchToken(for: rawToken)
        guard Self.isPlausibleAppToken(rawToken, normalized: matchToken) else {
            return nil
        }

        guard !Self.matchesInstalledApp(token: matchToken, bundleIdentifiers: bundleIdentifiers, appNameTokens: appNameTokens) else {
            return nil
        }

        let size = await sizer.size(of: url)
        guard size >= spec.minimumSize else {
            return nil
        }

        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .localizedNameKey])

        return OrphanedFileCandidate(
            url: url,
            displayName: values?.localizedName ?? url.lastPathComponent,
            identifierToken: matchToken,
            category: spec.category,
            sizeBytes: size,
            lastModified: values?.contentModificationDate,
            rationale: Self.rationale(for: spec.category, token: matchToken)
        )
    }

    private static func rawToken(for url: URL, category: OrphanedFileCategory) -> String? {
        let name = url.lastPathComponent

        switch category {
        case .preferences:
            guard name.hasSuffix(".plist") else { return nil }
            return String(name.dropLast(".plist".count))
        case .savedState:
            guard name.hasSuffix(".savedState") else { return nil }
            return String(name.dropLast(".savedState".count))
        case .applicationSupport, .caches, .containers, .groupContainers, .logs, .launchAgents:
            return name
        }
    }

    static func matchToken(for rawToken: String) -> String {
        let lower = rawToken.lowercased()
        if lower.hasPrefix("group.") {
            return String(lower.dropFirst("group.".count))
        }

        if lower.hasPrefix("application.") {
            return String(lower.dropFirst("application.".count))
        }

        return lower
    }

    static func normalizedAppNameToken(for name: String) -> String {
        name
            .replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private static func isPlausibleAppToken(_ rawToken: String, normalized: String) -> Bool {
        let blockedPrefixes = [
            "com.apple.",
            "group.com.apple.",
            "apple."
        ]
        let blockedExact = Set([
            "metadata",
            "fonts",
            "icons",
            "safari",
            "mail",
            "messages",
            "diagnosticreports",
            "desktop services store"
        ])

        if blockedPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return false
        }

        if blockedExact.contains(normalized) {
            return false
        }

        if normalized.contains(".") {
            let parts = normalized.split(separator: ".")
            return parts.count >= 3 && !parts.contains(where: { $0.isEmpty })
        }

        let compact = normalizedAppNameToken(for: rawToken)
        return compact.count >= 6
    }

    static func matchesInstalledApp(
        token: String,
        bundleIdentifiers: Set<String>,
        appNameTokens: Set<String>
    ) -> Bool {
        if bundleIdentifiers.contains(token) {
            return true
        }

        if bundleIdentifiers.contains(where: { token.hasPrefix($0 + ".") || $0.hasPrefix(token + ".") }) {
            return true
        }

        let compact = normalizedAppNameToken(for: token)
        if appNameTokens.contains(compact) {
            return true
        }

        return false
    }

    private static func rationale(for category: OrphanedFileCategory, token: String) -> String {
        switch category {
        case .applicationSupport:
            "Support data for \(token) still exists even though the app no longer appears installed."
        case .caches:
            "Cached data for \(token) is still present and may be reclaimable after uninstall."
        case .preferences:
            "Preference data for \(token) still exists without a matching installed app."
        case .containers:
            "Sandbox container for \(token) remains without a matching installed app."
        case .groupContainers:
            "Shared container for \(token) remains without a matching installed app."
        case .logs:
            "Logs for \(token) are still present after the app appears to be gone."
        case .savedState:
            "Saved window state for \(token) remains without a matching installed app."
        case .launchAgents:
            "User launch agent \(token) still exists even though the owning app no longer appears installed."
        }
    }
}
