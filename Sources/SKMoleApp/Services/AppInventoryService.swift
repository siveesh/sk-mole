import AppKit
import Foundation

actor AppInventoryService {
    private let fileManager = FileManager.default
    private let guardService: SystemGuard
    private let sizer: DirectorySizer
    private let home = FileManager.default.homeDirectoryForCurrentUser

    init(guardService: SystemGuard, sizer: DirectorySizer) {
        self.guardService = guardService
        self.sizer = sizer
    }

    func discoverApplications(progress: @escaping @Sendable (ScanProgress) async -> Void = { _ in }) async -> [InstalledApp] {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications")
        ]

        var appURLs: [URL] = []

        for root in roots where fileManager.fileExists(atPath: root.path) {
            if Task.isCancelled {
                return []
            }

            appURLs.append(contentsOf: findApplications(in: root))
        }

        var apps: [InstalledApp] = []
        let uniqueURLs = Array(Set(appURLs))

        for (index, url) in uniqueURLs.enumerated() {
            if Task.isCancelled {
                return Self.sortedApplications(apps)
            }

            await progress(
                ScanProgress(
                    title: "App inventory",
                    detail: "Inspecting \(url.deletingPathExtension().lastPathComponent)",
                    completedUnits: index + 1,
                    totalUnits: max(uniqueURLs.count, 1)
                )
            )

            if let app = await inspectApplication(at: url, requireManagedLocation: true) {
                apps.append(app)
            }
        }

        return Self.sortedApplications(apps)
    }

    func inspectApplication(at url: URL, requireManagedLocation: Bool = true) async -> InstalledApp? {
        let normalized = URLPathSafety.standardized(url)

        guard normalized.pathExtension == "app" else {
            return nil
        }

        guard fileManager.fileExists(atPath: normalized.path) else {
            return nil
        }

        if requireManagedLocation, !(await guardService.canOperate(on: normalized, purpose: .uninstall)) {
            return nil
        }

        let bundle = Bundle(url: normalized)
        let bundleIdentifier = bundle?.bundleIdentifier
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? normalized.deletingPathExtension().lastPathComponent
        let size = await sizer.size(of: normalized)
        let running = bundleIdentifier.flatMap { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false
        let protected = await guardService.isProtectedApplication(normalized, bundleIdentifier: bundleIdentifier)

        return InstalledApp(
            name: name,
            bundleIdentifier: bundleIdentifier,
            url: normalized,
            sizeBytes: size,
            isRunning: running,
            isProtected: protected,
            location: normalized.path.contains("/.Trash/") ? .trash : .managed
        )
    }

    func previewRemoval(for app: InstalledApp) async -> UninstallPreview {
        await preview(for: app, mode: .removeAppAndRemnants)
    }

    func previewReset(for app: InstalledApp) async -> UninstallPreview {
        await preview(for: app, mode: .resetApp)
    }

    func discoverTrashedApplications(progress: @escaping @Sendable (ScanProgress) async -> Void = { _ in }) async -> [InstalledApp] {
        let trashRoot = home.appendingPathComponent(".Trash")
        guard fileManager.fileExists(atPath: trashRoot.path) else {
            return []
        }

        let urls = findApplications(in: trashRoot)
        var apps: [InstalledApp] = []

        for (index, url) in Array(Set(urls)).enumerated() {
            if Task.isCancelled {
                return Self.sortedApplications(apps)
            }

            await progress(
                ScanProgress(
                    title: "Trash review",
                    detail: "Inspecting \(url.deletingPathExtension().lastPathComponent)",
                    completedUnits: index + 1,
                    totalUnits: max(urls.count, 1)
                )
            )

            if let app = await inspectApplication(at: url, requireManagedLocation: false) {
                apps.append(app)
            }
        }

        return Self.sortedApplications(apps)
    }

    func previewSmartDelete(for app: InstalledApp) async -> UninstallPreview {
        await preview(for: app, mode: .removeLeftoversOnly)
    }

    func remove(_ preview: UninstallPreview) async throws {
        guard !preview.app.isProtected else {
            throw NSError(
                domain: "SKMole.Uninstall",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Protected apps cannot be removed from SK Mole."]
            )
        }

        switch preview.mode {
        case .removeAppAndRemnants:
            try await guardService.moveToTrash(preview.app.url, purpose: .uninstall)
            for remnant in preview.remnants {
                try await guardService.moveToTrash(remnant.url, purpose: .uninstall)
            }
        case .resetApp, .removeLeftoversOnly:
            for remnant in preview.remnants {
                try await guardService.moveToTrash(remnant.url, purpose: .uninstall)
            }
        }
    }

    private func preview(for app: InstalledApp, mode: UninstallPreviewMode) async -> UninstallPreview {
        let exactCandidates = exactRemnantCandidates(for: app)
        let wildcardCandidates = relatedUserDomainCandidates(for: app)
        var remnants: [AppRemnant] = []

        for url in Array(Set(exactCandidates + wildcardCandidates)) where fileManager.fileExists(atPath: url.path) {
            guard await guardService.canOperate(on: url, purpose: .uninstall) else {
                continue
            }

            let size = await sizer.size(of: url)
            remnants.append(
                AppRemnant(
                    url: url,
                    displayName: url.lastPathComponent,
                    sizeBytes: size,
                    rationale: remnantReason(for: url),
                    safetyLevel: url.path.contains("/LaunchAgents/") ? .review : .safe
                )
            )
        }

        let deduplicated = Dictionary(grouping: remnants, by: \.url.path)
            .compactMap { $0.value.first }
            .sorted { $0.sizeBytes > $1.sizeBytes }

        return UninstallPreview(
            app: app,
            remnants: deduplicated,
            associatedItems: await associatedItems(for: app),
            mode: mode
        )
    }

    private func findApplications(in root: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var results: [URL] = []

        for case let url as URL in enumerator {
            if url.pathExtension == "app" {
                results.append(url)
                enumerator.skipDescendants()
            }
        }

        return results
    }

    private func exactRemnantCandidates(for app: InstalledApp) -> [URL] {
        var urls: [URL] = []
        let sanitizedName = app.name.replacingOccurrences(of: ".app", with: "")

        if let bundleIdentifier = app.bundleIdentifier {
            urls.append(contentsOf: [
                home.appendingPathComponent("Library/Application Support/\(bundleIdentifier)"),
                home.appendingPathComponent("Library/Caches/\(bundleIdentifier)"),
                home.appendingPathComponent("Library/Preferences/\(bundleIdentifier).plist"),
                home.appendingPathComponent("Library/Logs/\(bundleIdentifier)"),
                home.appendingPathComponent("Library/Saved Application State/\(bundleIdentifier).savedState"),
                home.appendingPathComponent("Library/Containers/\(bundleIdentifier)"),
                home.appendingPathComponent("Library/WebKit/\(bundleIdentifier)")
            ])
        }

        urls.append(contentsOf: [
            home.appendingPathComponent("Library/Application Support/\(sanitizedName)"),
            home.appendingPathComponent("Library/Caches/\(sanitizedName)"),
            home.appendingPathComponent("Library/Logs/\(sanitizedName)")
        ])

        return urls
    }

    private func relatedUserDomainCandidates(for app: InstalledApp) -> [URL] {
        guard let matcher = associationMatcher(for: app) else {
            return []
        }

        let wildcardRoots = [
            home.appendingPathComponent("Library/Containers"),
            home.appendingPathComponent("Library/Group Containers"),
            home.appendingPathComponent("Library/Application Scripts"),
            home.appendingPathComponent("Library/HTTPStorages"),
            home.appendingPathComponent("Library/Preferences/ByHost"),
            home.appendingPathComponent("Library/LaunchAgents")
        ]

        return wildcardRoots.flatMap { matchingEntries(in: $0, matcher: matcher) }
    }

    private func associatedItems(for app: InstalledApp) async -> [AssociatedAppItem] {
        let bundled = await bundledAssociatedItems(for: app)
        let adminScoped = await adminScopedAssociatedItems(for: app)

        return Dictionary(grouping: bundled + adminScoped, by: \.url.path)
            .compactMap { $0.value.first }
            .sorted { left, right in
                if left.disposition != right.disposition {
                    return left.disposition == .removedWithAppBundle
                }

                return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
            }
    }

    private func bundledAssociatedItems(for app: InstalledApp) async -> [AssociatedAppItem] {
        let specs: [(String, String, String)] = [
            ("Contents/Library/LoginItems", "person.crop.circle.badge.plus", "Bundled login item removed together with the main app bundle."),
            ("Contents/PlugIns", "puzzlepiece.extension", "Bundled extension or plugin contained inside the app bundle."),
            ("Contents/XPCServices", "bolt.horizontal.circle", "Bundled XPC service contained inside the app bundle."),
            ("Contents/Library/HelperTools", "lock.shield", "Bundled helper executable contained inside the app bundle."),
            ("Contents/Library/LaunchServices", "lock.shield", "Legacy bundled helper executable contained inside the app bundle.")
        ]

        var items: [AssociatedAppItem] = []

        for (relativePath, symbol, rationale) in specs {
            let root = app.url.appendingPathComponent(relativePath)
            let matches = (try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in matches {
                items.append(
                    AssociatedAppItem(
                        url: url,
                        displayName: url.lastPathComponent,
                        sizeBytes: await sizer.size(of: url),
                        rationale: rationale,
                        symbol: symbol,
                        disposition: .removedWithAppBundle
                    )
                )
            }
        }

        return items
    }

    private func adminScopedAssociatedItems(for app: InstalledApp) async -> [AssociatedAppItem] {
        guard let matcher = associationMatcher(for: app) else {
            return []
        }

        let roots: [(URL, String, String)] = [
            (URL(fileURLWithPath: "/Library/LaunchAgents"), "person.crop.circle.badge.plus", "Admin-scoped launch agent detected. Review separately if the app installed background services."),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), "gearshape.2", "Admin-scoped launch daemon detected. Review separately if the app installed background services."),
            (URL(fileURLWithPath: "/Library/PrivilegedHelperTools"), "lock.shield", "Privileged helper tool detected. Review separately because it sits outside user-domain cleanup.")
        ]

        var items: [AssociatedAppItem] = []

        for (root, symbol, rationale) in roots {
            for url in matchingEntries(in: root, matcher: matcher) {
                items.append(
                    AssociatedAppItem(
                        url: url,
                        displayName: url.lastPathComponent,
                        sizeBytes: await sizer.size(of: url),
                        rationale: rationale,
                        symbol: symbol,
                        disposition: .reviewOnly
                    )
                )
            }
        }

        return items
    }

    private func matchingEntries(in root: URL, matcher: (String) -> Bool) -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else {
            return []
        }

        let entries = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return entries.filter { matcher($0.lastPathComponent) }
    }

    private func associationMatcher(for app: InstalledApp) -> ((String) -> Bool)? {
        let sanitizedName = app.name.replacingOccurrences(of: ".app", with: "").lowercased()
        let compactName = sanitizedName.replacingOccurrences(of: " ", with: "")
        let bundleIdentifier = app.bundleIdentifier?.lowercased()

        guard !sanitizedName.isEmpty || bundleIdentifier != nil else {
            return nil
        }

        return { fileName in
            let lower = fileName.lowercased()

            if let bundleIdentifier {
                if lower == bundleIdentifier || lower.hasPrefix(bundleIdentifier + ".") || lower.hasPrefix(bundleIdentifier + "-") || lower.contains(bundleIdentifier) {
                    return true
                }
            }

            if lower == sanitizedName || lower.hasPrefix(sanitizedName + ".") || lower.hasPrefix(sanitizedName + " ") {
                return true
            }

            return !compactName.isEmpty && lower.replacingOccurrences(of: " ", with: "").contains(compactName)
        }
    }

    private func remnantReason(for url: URL) -> String {
        switch url.path {
        case let path where path.contains("/Application Support/"):
            "App support files left behind after removing the main bundle."
        case let path where path.contains("/Caches/"):
            "Per-app cache content that can be rebuilt if the app is reinstalled."
        case let path where path.contains("/Preferences/"):
            "User defaults and preference storage."
        case let path where path.contains("/Saved Application State/"):
            "Saved restoration state from prior launches."
        case let path where path.contains("/Containers/"):
            "Sandbox container tied to the app bundle identifier."
        case let path where path.contains("/Group Containers/"):
            "Shared container tied to the app bundle identifier family."
        case let path where path.contains("/Application Scripts/"):
            "Automation scripts and extension scripts associated with the app."
        case let path where path.contains("/HTTPStorages/"):
            "Stored network caches or sessions left behind by the app."
        case let path where path.contains("/LaunchAgents/"):
            "User launch agent or login-item helper tied to the app."
        default:
            "App-specific leftover discovered in a user-scoped support location."
        }
    }

    private static func sortedApplications(_ apps: [InstalledApp]) -> [InstalledApp] {
        apps.sorted {
            let nameComparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            return $0.url.path.localizedCaseInsensitiveCompare($1.url.path) == .orderedAscending
        }
    }
}
