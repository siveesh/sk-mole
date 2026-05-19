import CoreServices
import Foundation
import SKMoleShared

actor AppUpdateService {
    static let selfUpdateItemID = "self:sk-mole"

    private static let selfBundleIdentifier = "com.siveesh.skmole"
    private static let selfRepositoryOwner = "siveesh"
    private static let selfRepositoryName = "sk-mole"
    private static let selfRepositoryPath = "\(selfRepositoryOwner)/\(selfRepositoryName)"

    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func scan(
        applications: [InstalledApp],
        homebrewInventory: HomebrewInventory?,
        progress: @escaping @Sendable (ScanProgress) async -> Void = { _ in }
    ) async throws -> AppUpdateReport {
        let appStoreAutomation = try await detectAppStoreAutomationStatus()
        let packageItems = homebrewItems(from: homebrewInventory)
        let managedByHomebrew = homebrewManagedApplicationKeys(from: homebrewInventory)
        let appCandidates = applications.filter {
            $0.bundleIdentifier != Self.selfBundleIdentifier
                && !isLikelyManagedByHomebrew($0, keys: managedByHomebrew)
        }
        let selfUpdateItem = await evaluateSelfUpdate()

        let totalUnits = max(packageItems.count + appCandidates.count + 1, 1)
        var completedUnits = 0

        await progress(
            ScanProgress(
                title: "Update scan",
                detail: "Preparing update sources",
                completedUnits: 0,
                totalUnits: totalUnits
            )
        )

        if !packageItems.isEmpty {
            completedUnits = packageItems.count
            await progress(
                ScanProgress(
                    title: "Update scan",
                    detail: "Prepared \(packageItems.count) Homebrew package entries",
                    completedUnits: completedUnits,
                    totalUnits: totalUnits
                )
            )
        }

        completedUnits = min(totalUnits, completedUnits + 1)
        await progress(
            ScanProgress(
                title: "Update scan",
                detail: "Checked SK Mole GitHub release",
                completedUnits: completedUnits,
                totalUnits: totalUnits
            )
        )

        var applicationItems: [AppUpdateItem] = []

        for (index, app) in appCandidates.enumerated() {
            if Task.isCancelled {
                break
            }

            let item = await evaluateApplication(app, appStoreAutomation: appStoreAutomation)
            applicationItems.append(item)
            completedUnits = min(totalUnits, packageItems.count + 1 + index + 1)

            await progress(
                ScanProgress(
                    title: "Update scan",
                    detail: "Checked \(app.name)",
                    completedUnits: completedUnits,
                    totalUnits: totalUnits
                )
            )
        }

        let items = (packageItems + [selfUpdateItem] + applicationItems).sorted(by: Self.sortItems)

        return AppUpdateReport(
            scannedAt: .now,
            appStoreAutomation: appStoreAutomation,
            scannedApplicationCount: applicationItems.count + 1,
            scannedPackageCount: packageItems.count,
            items: items
        )
    }

    func runMacAppStoreUpdate(arguments: [String], actionTitle: String) async -> OptimizationLog {
        do {
            let status = try await detectAppStoreAutomationStatus()
            guard let executablePath = status.executablePath else {
                return OptimizationLog(
                    actionTitle: actionTitle,
                    output: "Install `mas` first to automate App Store updates from SK Mole.",
                    succeeded: false,
                    timestamp: .now
                )
            }

            let result = try await runProcess(executable: executablePath, arguments: arguments)
            let output = result.output.isEmpty ? "Completed without terminal output." : result.output
            return OptimizationLog(
                actionTitle: actionTitle,
                output: output,
                succeeded: result.terminationStatus == 0,
                timestamp: .now
            )
        } catch {
            return OptimizationLog(
                actionTitle: actionTitle,
                output: error.localizedDescription,
                succeeded: false,
                timestamp: .now
            )
        }
    }

    func downloadSelfUpdateInstaller(from url: URL, latestVersion: String?) async -> (log: OptimizationLog, installerURL: URL?) {
        do {
            let request = try makeRequest(url: url)
            let (temporaryURL, response) = try await downloadLimitedFile(
                for: request,
                limit: 250 * 1_024 * 1_024,
                source: "SK Mole GitHub release"
            )

            let suggestedName = response.suggestedFilename?.trimmingCharacters(in: .whitespacesAndNewlines)
            let version = latestVersion.flatMap(Self.normalizedVersion) ?? "latest"
            let fileName = sanitizedInstallerFileName(suggestedName, version: version)
            let downloadsDirectory = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
            try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)

            let destination = downloadsDirectory.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }

            try fileManager.moveItem(at: temporaryURL, to: destination)

            return (
                OptimizationLog(
                    actionTitle: "Download SK Mole Update",
                    output: "Downloaded SK Mole \(version) to \(destination.path). The disk image was opened so you can drag the new app into Applications.",
                    succeeded: true,
                    timestamp: .now
                ),
                destination
            )
        } catch {
            return (
                OptimizationLog(
                    actionTitle: "Download SK Mole Update",
                    output: error.localizedDescription,
                    succeeded: false,
                    timestamp: .now
                ),
                nil
            )
        }
    }

    static func normalizedVersion(_ value: String?) -> String? {
        guard var trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            trimmed.removeFirst()
        }

        if let whitespace = trimmed.firstIndex(where: \.isWhitespace) {
            trimmed = String(trimmed[..<whitespace])
        }

        return trimmed.isEmpty ? nil : trimmed
    }

    static func compareVersions(_ installed: String?, _ latest: String?) -> ComparisonResult {
        guard
            let installed = normalizedVersion(installed),
            let latest = normalizedVersion(latest)
        else {
            return .orderedSame
        }

        return installed.compare(latest, options: [.numeric, .caseInsensitive])
    }

    private static func sortItems(_ left: AppUpdateItem, _ right: AppUpdateItem) -> Bool {
        let leftPriority = statusPriority(left.status)
        let rightPriority = statusPriority(right.status)

        if leftPriority != rightPriority {
            return leftPriority < rightPriority
        }

        if left.kind != right.kind {
            return left.kind.rawValue < right.kind.rawValue
        }

        return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
    }

    private static func statusPriority(_ status: AppUpdateStatusKind) -> Int {
        switch status {
        case .updateAvailable: 0
        case .manualCheck: 1
        case .error: 2
        case .upToDate: 3
        case .unsupported: 4
        }
    }

    private func homebrewItems(from inventory: HomebrewInventory?) -> [AppUpdateItem] {
        guard let inventory else {
            return []
        }

        return inventory.installedPackages.map { package in
            let status: AppUpdateStatusKind = package.isOutdated ? .updateAvailable : .upToDate
            let detail: String
            if package.isOutdated {
                detail = "A newer Homebrew \(package.kind.title.lowercased()) is available."
            } else {
                detail = "This Homebrew \(package.kind.title.lowercased()) matches the latest known version."
            }

            return AppUpdateItem(
                id: "brew:\(package.id)",
                kind: .package,
                displayName: package.displayName,
                bundleIdentifier: nil,
                installedVersion: package.installedVersion,
                latestVersion: package.latestVersion,
                sourceKind: .homebrew,
                status: status,
                detail: detail,
                sourceDescription: package.kind.title,
                appURL: nil,
                homepageURL: package.homepage,
                primaryURL: package.homepage,
                primaryURLTitle: package.homepage == nil ? nil : "Open Homepage",
                secondaryURL: nil,
                secondaryURLTitle: nil,
                homebrewReference: package.reference,
                appStoreAdamID: nil,
                commandPreview: package.isOutdated ? package.upgradeCommand : nil,
                canAutoInstall: package.isOutdated,
                releaseNotesSummary: nil,
                releaseNotesURL: nil,
                releaseNotesURLTitle: nil,
                fullReleaseNotesURL: nil,
                fullReleaseNotesURLTitle: nil,
                publishedAt: nil
            )
        }
    }

    private func homebrewManagedApplicationKeys(from inventory: HomebrewInventory?) -> Set<String> {
        guard let inventory else {
            return []
        }

        var keys: Set<String> = []
        for package in inventory.installedPackages where package.kind == .cask {
            keys.insert(normalizedApplicationKey(package.displayName))
            keys.insert(normalizedApplicationKey(package.token))
        }

        return keys
    }

    private func isLikelyManagedByHomebrew(_ app: InstalledApp, keys: Set<String>) -> Bool {
        keys.contains(normalizedApplicationKey(app.name))
    }

    private func normalizedApplicationKey(_ value: String) -> String {
        value
            .replacingOccurrences(of: ".app", with: "", options: [.caseInsensitive])
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
    }

    private func evaluateApplication(
        _ app: InstalledApp,
        appStoreAutomation: AppStoreAutomationStatus
    ) async -> AppUpdateItem {
        let bundle = Bundle(url: app.url)
        let installedVersion = Self.normalizedVersion(
            (bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        )
        let homepageURL = preferredHomepageURL(for: bundle)
        let sparkleFeedURL = sparkleFeedURL(for: bundle)
        let hasAppStoreReceipt = fileManager.fileExists(
            atPath: app.url.appendingPathComponent("Contents/_MASReceipt/receipt").path
        )
        let appStoreAdamID = hasAppStoreReceipt ? appStoreAdamID(for: app.url) : nil

        if hasAppStoreReceipt || appStoreAdamID != nil {
            return await evaluateAppStoreApplication(
                app,
                installedVersion: installedVersion,
                adamID: appStoreAdamID,
                appStoreAutomation: appStoreAutomation,
                homepageURL: homepageURL
            )
        }

        if let sparkleFeedURL {
            if let item = await evaluateSparkleApplication(
                app,
                installedVersion: installedVersion,
                feedURL: sparkleFeedURL,
                homepageURL: homepageURL
            ) {
                return item
            }
        }

        if let repositoryURL = githubRepositoryURL(from: [homepageURL, sparkleFeedURL]) {
            if let item = await evaluateGitHubApplication(
                app,
                installedVersion: installedVersion,
                repositoryURL: repositoryURL,
                homepageURL: homepageURL
            ) {
                return item
            }
        }

        if let homepageURL {
            return AppUpdateItem(
                id: "app:\(app.id)",
                kind: .application,
                displayName: app.name,
                bundleIdentifier: app.bundleIdentifier,
                installedVersion: installedVersion,
                latestVersion: nil,
                sourceKind: .vendor,
                status: .manualCheck,
                detail: "No structured appcast or GitHub release source was detected, so SK Mole can only open the vendor site for a manual check.",
                sourceDescription: homepageURL.host ?? "Vendor site",
                appURL: app.url,
                homepageURL: homepageURL,
                primaryURL: homepageURL,
                primaryURLTitle: "Open Vendor Site",
                secondaryURL: nil,
                secondaryURLTitle: nil,
                homebrewReference: nil,
                appStoreAdamID: nil,
                commandPreview: nil,
                canAutoInstall: false,
                releaseNotesSummary: nil,
                releaseNotesURL: nil,
                releaseNotesURLTitle: nil,
                fullReleaseNotesURL: nil,
                fullReleaseNotesURLTitle: nil,
                publishedAt: nil
            )
        }

        return AppUpdateItem(
            id: "app:\(app.id)",
            kind: .application,
            displayName: app.name,
            bundleIdentifier: app.bundleIdentifier,
            installedVersion: installedVersion,
            latestVersion: nil,
            sourceKind: .unknown,
            status: .unsupported,
            detail: "SK Mole could not find App Store metadata, a Sparkle feed, a GitHub repository, or a vendor site inside this bundle.",
            sourceDescription: "No structured source",
            appURL: app.url,
            homepageURL: nil,
            primaryURL: nil,
            primaryURLTitle: nil,
            secondaryURL: nil,
            secondaryURLTitle: nil,
            homebrewReference: nil,
            appStoreAdamID: nil,
            commandPreview: nil,
            canAutoInstall: false,
            releaseNotesSummary: nil,
            releaseNotesURL: nil,
            releaseNotesURLTitle: nil,
            fullReleaseNotesURL: nil,
            fullReleaseNotesURLTitle: nil,
            publishedAt: nil
        )
    }

    private func evaluateAppStoreApplication(
        _ app: InstalledApp,
        installedVersion: String?,
        adamID: Int?,
        appStoreAutomation: AppStoreAutomationStatus,
        homepageURL: URL?
    ) async -> AppUpdateItem {
        guard let adamID else {
            return AppUpdateItem(
                id: "appstore:\(app.id)",
                kind: .application,
                displayName: app.name,
                bundleIdentifier: app.bundleIdentifier,
                installedVersion: installedVersion,
                latestVersion: nil,
                sourceKind: .appStore,
                status: .manualCheck,
                detail: "An App Store receipt was found, but SK Mole could not recover the store identifier needed for a direct version lookup.",
                sourceDescription: "Mac App Store",
                appURL: app.url,
                homepageURL: homepageURL,
                primaryURL: nil,
                primaryURLTitle: nil,
                secondaryURL: homepageURL,
                secondaryURLTitle: homepageURL == nil ? nil : "Open Vendor Site",
                homebrewReference: nil,
                appStoreAdamID: nil,
                commandPreview: nil,
                canAutoInstall: false,
                releaseNotesSummary: nil,
                releaseNotesURL: nil,
                releaseNotesURLTitle: nil,
                fullReleaseNotesURL: nil,
                fullReleaseNotesURLTitle: nil,
                publishedAt: nil
            )
        }

        let fallbackStoreURL = URL(string: "macappstore://itunes.apple.com/app/id\(adamID)")

        do {
            let metadata = try await fetchAppStoreMetadata(adamID: adamID)
            let latestVersion = Self.normalizedVersion(metadata.version)
            let comparison = Self.compareVersions(installedVersion, latestVersion)
            let isUpdateAvailable = comparison == .orderedAscending
            let storeURL = URL(string: "macappstore://itunes.apple.com/app/id\(adamID)") ?? metadata.trackViewURL

            let detail: String
            if isUpdateAvailable {
                if appStoreAutomation.canInstallUpdates {
                    detail = "A newer Mac App Store build is available and can be installed with `mas`."
                } else if appStoreAutomation.isInstalled {
                    detail = "A newer Mac App Store build is available, but `mas` does not appear signed in on this Mac yet."
                } else {
                    detail = "A newer Mac App Store build is available. Install `mas` to let SK Mole automate these updates."
                }
            } else {
                detail = "The installed App Store version matches the latest version Apple currently reports."
            }

            return AppUpdateItem(
                id: "appstore:\(adamID)",
                kind: .application,
                displayName: app.name,
                bundleIdentifier: app.bundleIdentifier,
                installedVersion: installedVersion,
                latestVersion: latestVersion,
                sourceKind: .appStore,
                status: isUpdateAvailable ? .updateAvailable : .upToDate,
                detail: detail,
                sourceDescription: "Mac App Store",
                appURL: app.url,
                homepageURL: metadata.trackViewURL,
                primaryURL: storeURL,
                primaryURLTitle: "Open App Store",
                secondaryURL: metadata.trackViewURL,
                secondaryURLTitle: metadata.trackViewURL == nil ? nil : "Open Store Page",
                homebrewReference: nil,
                appStoreAdamID: adamID,
                commandPreview: isUpdateAvailable && appStoreAutomation.canInstallUpdates ? "mas upgrade \(adamID)" : nil,
                canAutoInstall: isUpdateAvailable && appStoreAutomation.canInstallUpdates,
                releaseNotesSummary: sanitizedReleaseNotes(metadata.releaseNotes),
                releaseNotesURL: metadata.trackViewURL,
                releaseNotesURLTitle: metadata.trackViewURL == nil ? nil : "Open Store Notes",
                fullReleaseNotesURL: metadata.artistViewURL,
                fullReleaseNotesURLTitle: metadata.artistViewURL == nil ? nil : "Vendor Page",
                publishedAt: metadata.currentVersionReleaseDate
            )
        } catch {
            return AppUpdateItem(
                id: "appstore:\(adamID)",
                kind: .application,
                displayName: app.name,
                bundleIdentifier: app.bundleIdentifier,
                installedVersion: installedVersion,
                latestVersion: nil,
                sourceKind: .appStore,
                status: .manualCheck,
                detail: "App Store lookup failed, so SK Mole is falling back to opening the store page directly. \(error.localizedDescription)",
                sourceDescription: "Mac App Store",
                appURL: app.url,
                homepageURL: homepageURL,
                primaryURL: fallbackStoreURL,
                primaryURLTitle: "Open App Store",
                secondaryURL: homepageURL,
                secondaryURLTitle: homepageURL == nil ? nil : "Open Vendor Site",
                homebrewReference: nil,
                appStoreAdamID: adamID,
                commandPreview: nil,
                canAutoInstall: false,
                releaseNotesSummary: nil,
                releaseNotesURL: fallbackStoreURL,
                releaseNotesURLTitle: fallbackStoreURL == nil ? nil : "Open App Store",
                fullReleaseNotesURL: homepageURL,
                fullReleaseNotesURLTitle: homepageURL == nil ? nil : "Vendor Page",
                publishedAt: nil
            )
        }
    }

    private func evaluateSparkleApplication(
        _ app: InstalledApp,
        installedVersion: String?,
        feedURL: URL,
        homepageURL: URL?
    ) async -> AppUpdateItem? {
        do {
            let feed = try await fetchSparkleFeed(from: feedURL)
            guard let latestVersion = Self.normalizedVersion(feed.latestVersion) else {
                return nil
            }

            let isUpdateAvailable = Self.compareVersions(installedVersion, latestVersion) == .orderedAscending
            let primaryURL = feed.downloadURL ?? feed.releaseNotesURL ?? feed.itemURL ?? homepageURL ?? feedURL
            let primaryTitle: String
            if feed.downloadURL != nil {
                primaryTitle = "Download"
            } else if feed.releaseNotesURL != nil || feed.itemURL != nil {
                primaryTitle = "Open Release"
            } else {
                primaryTitle = "Open Appcast"
            }

            let detail = isUpdateAvailable
                ? "A newer version was found in the app's Sparkle feed. SK Mole can alert you here, but the vendor still controls the actual install flow."
                : "The installed version matches the newest version exposed by the app's Sparkle feed."

            return AppUpdateItem(
                id: "sparkle:\(app.id)",
                kind: .application,
                displayName: app.name,
                bundleIdentifier: app.bundleIdentifier,
                installedVersion: installedVersion,
                latestVersion: latestVersion,
                sourceKind: .sparkle,
                status: isUpdateAvailable ? .updateAvailable : .upToDate,
                detail: detail,
                sourceDescription: feedURL.host ?? "Sparkle appcast",
                appURL: app.url,
                homepageURL: homepageURL,
                primaryURL: primaryURL,
                primaryURLTitle: primaryTitle,
                secondaryURL: feedURL,
                secondaryURLTitle: "Open Appcast",
                homebrewReference: nil,
                appStoreAdamID: nil,
                commandPreview: nil,
                canAutoInstall: false,
                releaseNotesSummary: sanitizedReleaseNotes(feed.embeddedReleaseNotes),
                releaseNotesURL: feed.releaseNotesURL ?? feed.itemURL,
                releaseNotesURLTitle: feed.releaseNotesURL != nil ? "Open Notes" : (feed.itemURL == nil ? nil : "Open Release"),
                fullReleaseNotesURL: feed.fullReleaseNotesURL,
                fullReleaseNotesURLTitle: feed.fullReleaseNotesURL == nil ? nil : "Full History",
                publishedAt: nil
            )
        } catch {
            SKMoleLog.maintenance.error("Sparkle update check failed for \(app.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func evaluateGitHubApplication(
        _ app: InstalledApp,
        installedVersion: String?,
        repositoryURL: URL,
        homepageURL: URL?
    ) async -> AppUpdateItem? {
        do {
            let release = try await fetchLatestGitHubRelease(repositoryURL: repositoryURL)
            let latestVersion = Self.normalizedVersion(release.tagName) ?? Self.normalizedVersion(release.name)
            let isUpdateAvailable = Self.compareVersions(installedVersion, latestVersion) == .orderedAscending

            let detail: String
            if isUpdateAvailable {
                detail = "A newer GitHub release was found for this app. SK Mole can open the release page or download source, but installation still depends on the vendor's distribution format."
            } else {
                detail = "The installed version matches the latest GitHub release SK Mole could find."
            }

            return AppUpdateItem(
                id: "github:\(app.id)",
                kind: .application,
                displayName: app.name,
                bundleIdentifier: app.bundleIdentifier,
                installedVersion: installedVersion,
                latestVersion: latestVersion,
                sourceKind: .github,
                status: isUpdateAvailable ? .updateAvailable : .upToDate,
                detail: detail,
                sourceDescription: repositoryURL.absoluteString,
                appURL: app.url,
                homepageURL: homepageURL ?? repositoryURL,
                primaryURL: release.htmlURL ?? repositoryURL,
                primaryURLTitle: "Open GitHub Release",
                secondaryURL: repositoryURL,
                secondaryURLTitle: "Open Repository",
                homebrewReference: nil,
                appStoreAdamID: nil,
                commandPreview: nil,
                canAutoInstall: false,
                releaseNotesSummary: sanitizedReleaseNotes(release.body),
                releaseNotesURL: release.htmlURL ?? repositoryURL,
                releaseNotesURLTitle: (release.htmlURL ?? repositoryURL) == repositoryURL ? "Open Release" : "Open Release Notes",
                fullReleaseNotesURL: repositoryURL,
                fullReleaseNotesURLTitle: "Repository",
                publishedAt: release.publishedAt
            )
        } catch {
            SKMoleLog.maintenance.error("GitHub release check failed for \(app.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func evaluateSelfUpdate() async -> AppUpdateItem {
        let installedVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let appURL = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.bundleURL : nil

        do {
            let repositoryURL = try Self.selfRepositoryURL()
            let release = try await fetchLatestGitHubRelease(repositoryURL: repositoryURL)
            let latestVersion = Self.normalizedVersion(release.tagName) ?? Self.normalizedVersion(release.name)
            let isUpdateAvailable = Self.compareVersions(installedVersion, latestVersion) == .orderedAscending
            let installerAsset = release.preferredInstallerAsset

            let detail: String
            if isUpdateAvailable, installerAsset?.downloadURL != nil {
                detail = "A newer SK Mole GitHub release is available. SK Mole can download the release DMG, open it, and guide you through replacing the app in Applications."
            } else if isUpdateAvailable {
                detail = "A newer SK Mole GitHub release is available, but no DMG asset was found. Open the release page to download it manually."
            } else {
                detail = "This SK Mole build matches the latest GitHub release."
            }

            return AppUpdateItem(
                id: Self.selfUpdateItemID,
                kind: .application,
                displayName: "SK Mole",
                bundleIdentifier: Self.selfBundleIdentifier,
                installedVersion: installedVersion,
                latestVersion: latestVersion,
                sourceKind: .github,
                status: isUpdateAvailable ? .updateAvailable : .upToDate,
                detail: detail,
                sourceDescription: "GitHub Releases",
                appURL: appURL,
                homepageURL: repositoryURL,
                primaryURL: installerAsset?.downloadURL ?? release.htmlURL ?? repositoryURL,
                primaryURLTitle: installerAsset?.downloadURL == nil ? "Open Release" : "Download DMG",
                secondaryURL: release.htmlURL ?? repositoryURL,
                secondaryURLTitle: "Release Notes",
                homebrewReference: nil,
                appStoreAdamID: nil,
                commandPreview: installerAsset?.downloadURL == nil ? nil : "Auto-checks GitHub Releases and downloads the latest SK Mole DMG.",
                canAutoInstall: isUpdateAvailable && installerAsset?.downloadURL != nil,
                releaseNotesSummary: sanitizedReleaseNotes(release.body),
                releaseNotesURL: release.htmlURL ?? repositoryURL,
                releaseNotesURLTitle: "Open Release Notes",
                fullReleaseNotesURL: repositoryURL.appendingPathComponent("releases"),
                fullReleaseNotesURLTitle: "All Releases",
                publishedAt: release.publishedAt
            )
        } catch {
            return AppUpdateItem(
                id: Self.selfUpdateItemID,
                kind: .application,
                displayName: "SK Mole",
                bundleIdentifier: Self.selfBundleIdentifier,
                installedVersion: installedVersion,
                latestVersion: nil,
                sourceKind: .github,
                status: .error,
                detail: "SK Mole could not check its own GitHub release feed. \(error.localizedDescription)",
                sourceDescription: "GitHub Releases",
                appURL: appURL,
                homepageURL: try? Self.selfRepositoryURL(),
                primaryURL: try? Self.selfRepositoryURL(),
                primaryURLTitle: "Open Repository",
                secondaryURL: nil,
                secondaryURLTitle: nil,
                homebrewReference: nil,
                appStoreAdamID: nil,
                commandPreview: nil,
                canAutoInstall: false,
                releaseNotesSummary: nil,
                releaseNotesURL: nil,
                releaseNotesURLTitle: nil,
                fullReleaseNotesURL: nil,
                fullReleaseNotesURLTitle: nil,
                publishedAt: nil
            )
        }
    }

    private func preferredHomepageURL(for bundle: Bundle?) -> URL? {
        let keys = [
            "SUHomepageURL",
            "HomepageURL",
            "HomePageURL",
            "WebsiteURL",
            "WebSiteURL"
        ]

        for key in keys {
            if let value = bundle?.object(forInfoDictionaryKey: key) as? String,
               let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
               url.scheme?.hasPrefix("http") == true {
                return url
            }
        }

        return nil
    }

    private func sparkleFeedURL(for bundle: Bundle?) -> URL? {
        let keys = ["SUFeedURL", "SUOriginalFeedURL"]

        for key in keys {
            if let value = bundle?.object(forInfoDictionaryKey: key) as? String,
               let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
               url.scheme?.hasPrefix("http") == true {
                return url
            }
        }

        return nil
    }

    private func appStoreAdamID(for appURL: URL) -> Int? {
        guard let item = MDItemCreate(nil, appURL.path as CFString),
              let value = MDItemCopyAttribute(item, "kMDItemAppStoreAdamID" as CFString) else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        if let string = value as? String {
            return Int(string)
        }

        return nil
    }

    private func githubRepositoryURL(from urls: [URL?]) -> URL? {
        for candidate in urls.compactMap({ $0 }) {
            guard let host = candidate.host?.lowercased() else {
                continue
            }

            let components = candidate.pathComponents.filter { $0 != "/" }

            if host == "github.com", components.count >= 2 {
                return URL(string: "https://github.com/\(components[0])/\(components[1])")
            }

            if host == "raw.githubusercontent.com", components.count >= 2 {
                return URL(string: "https://github.com/\(components[0])/\(components[1])")
            }
        }

        return nil
    }

    private func fetchAppStoreMetadata(adamID: Int) async throws -> AppStoreLookupResult {
        let primaryRegion = Locale.current.region?.identifier.lowercased() ?? "us"
        let fallbackRegions = Array(NSOrderedSet(array: [primaryRegion, "us"])).compactMap { $0 as? String }

        for region in fallbackRegions {
            guard var components = URLComponents(string: "https://itunes.apple.com/lookup") else {
                throw AppUpdateError.lookupFailed("Unable to build the App Store lookup URL.")
            }
            components.queryItems = [
                URLQueryItem(name: "id", value: String(adamID)),
                URLQueryItem(name: "country", value: region),
                URLQueryItem(name: "entity", value: "macSoftware")
            ]

            let request = try makeRequest(url: try components.requireURL())
            let (data, _) = try await fetchLimitedData(
                for: request,
                limit: 1 * 1_024 * 1_024,
                source: "App Store lookup"
            )
            let payload = try decoder.decode(AppStoreLookupPayload.self, from: data)

            if let first = payload.results.first {
                return first
            }
        }

        throw AppUpdateError.lookupFailed("Apple did not return a lookup result for App Store ID \(adamID).")
    }

    private func fetchSparkleFeed(from url: URL) async throws -> SparkleFeedSummary {
        let request = try makeRequest(url: url)
        let (data, _) = try await fetchLimitedData(
            for: request,
            limit: 2 * 1_024 * 1_024,
            source: "Sparkle appcast"
        )
        let parser = SparkleAppcastParser(baseURL: url)
        return try parser.parse(data: data)
    }

    private func fetchLatestGitHubRelease(repositoryURL: URL) async throws -> GitHubRelease {
        let components = repositoryURL.pathComponents.filter { $0 != "/" }
        guard components.count >= 2 else {
            throw AppUpdateError.lookupFailed("GitHub repository URL is missing an owner or repository name.")
        }

        var apiComponents = URLComponents()
        apiComponents.scheme = "https"
        apiComponents.host = "api.github.com"
        apiComponents.path = "/repos/\(components[0])/\(components[1])/releases/latest"
        guard let apiURL = apiComponents.url else {
            throw AppUpdateError.lookupFailed("Unable to build the GitHub release lookup URL.")
        }
        var request = try makeRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SK Mole", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await fetchLimitedData(
            for: request,
            limit: 2 * 1_024 * 1_024,
            source: "GitHub release"
        )

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
            throw AppUpdateError.lookupFailed("This repository does not expose a latest GitHub release.")
        }

        return try decoder.decode(GitHubRelease.self, from: data)
    }

    private func fetchLimitedData(
        for request: URLRequest,
        limit: Int,
        source: String
    ) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)

        if response.expectedContentLength > Int64(limit) {
            throw AppUpdateError.lookupFailed("\(source) advertised \(ByteCountFormatter.string(fromByteCount: response.expectedContentLength, countStyle: .file)), which is larger than SK Mole's safety limit.")
        }

        var data = Data()
        data.reserveCapacity(min(limit, 64 * 1_024))

        for try await byte in bytes {
            data.append(byte)
            if data.count > limit {
                throw AppUpdateError.lookupFailed("\(source) exceeded \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)), so SK Mole stopped reading it.")
            }
        }

        return (data, response)
    }

    private func downloadLimitedFile(
        for request: URLRequest,
        limit: Int64,
        source: String
    ) async throws -> (URL, URLResponse) {
        let (temporaryURL, response) = try await session.download(for: request)

        if response.expectedContentLength > limit {
            try? fileManager.removeItem(at: temporaryURL)
            throw AppUpdateError.lookupFailed("\(source) advertised \(ByteCountFormatter.string(fromByteCount: response.expectedContentLength, countStyle: .file)), which is larger than SK Mole's safety limit.")
        }

        let fileSize = (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if Int64(fileSize) > limit {
            try? fileManager.removeItem(at: temporaryURL)
            throw AppUpdateError.lookupFailed("\(source) exceeded \(ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)), so SK Mole deleted the partial download.")
        }

        return (temporaryURL, response)
    }

    private func detectAppStoreAutomationStatus() async throws -> AppStoreAutomationStatus {
        let path = try await detectExecutable(named: "mas")
        guard let path else {
            return AppStoreAutomationStatus(executablePath: nil, version: nil, accountName: nil, accountDetail: nil)
        }

        let versionResult = try await runProcess(executable: path, arguments: ["version"])
        let accountResult = try await runProcess(executable: path, arguments: ["account"])
        let version = versionResult.output
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let accountOutput = accountResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountName: String?
        if accountResult.terminationStatus == 0, !accountOutput.isEmpty {
            accountName = accountOutput
        } else {
            accountName = nil
        }

        return AppStoreAutomationStatus(
            executablePath: path,
            version: version,
            accountName: accountName,
            accountDetail: accountOutput.isEmpty ? nil : accountOutput
        )
    }

    private func detectExecutable(named executableName: String) async throws -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(executableName)",
            "/usr/local/bin/\(executableName)",
            "/usr/bin/\(executableName)"
        ]

        if let knownPath = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return knownPath
        }

        let probes: [(String, [String])] = [
            ("/bin/zsh", ["-ilc", "command -v \(executableName) 2>/dev/null || true"]),
            ("/bin/zsh", ["-lc", "command -v \(executableName) 2>/dev/null || true"]),
            ("/bin/bash", ["-lc", "command -v \(executableName) 2>/dev/null || true"])
        ]

        for (executable, arguments) in probes {
            let result = try await runProcess(executable: executable, arguments: arguments)
            guard result.terminationStatus == 0 else {
                continue
            }

            let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func makeRequest(url: URL) throws -> URLRequest {
        guard url.scheme == "https" else {
            throw AppUpdateError.insecureURL(url.absoluteString)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private static func selfRepositoryURL() throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(selfRepositoryPath)"

        guard let url = components.url else {
            throw AppUpdateError.malformedURL
        }

        return url
    }

    private func sanitizedInstallerFileName(_ suggestedName: String?, version: String) -> String {
        let fallback = "SK-Mole-\(version).dmg"
        let candidate: String
        if let suggestedName, !suggestedName.isEmpty {
            candidate = suggestedName
        } else {
            candidate = fallback
        }
        let safeName = candidate
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard safeName.lowercased().hasSuffix(".dmg"), !safeName.isEmpty else {
            return fallback
        }

        return safeName
    }

    private func sanitizedReleaseNotes(_ value: String?) -> String? {
        guard var notes = value?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else {
            return nil
        }

        notes = notes.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        notes = notes.replacingOccurrences(of: "&nbsp;", with: " ")
        notes = notes.replacingOccurrences(of: "&amp;", with: "&")
        notes = notes.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.count > 1_200 {
            return String(notes.prefix(1_200)) + "..."
        }
        return notes
    }

    private func runProcess(executable: String, arguments: [String]) async throws -> ProcessResult {
        let result = try await ProcessRunner.run(
            executable: executable,
            arguments: arguments,
            environment: Self.processEnvironment(for: executable),
            timeout: timeout(for: arguments),
            maxOutputBytes: 8 * 1_024 * 1_024
        )
        return ProcessResult(output: result.output, terminationStatus: result.terminationStatus)
    }

    private func timeout(for arguments: [String]) -> TimeInterval {
        if arguments.contains("upgrade") {
            return 600
        }
        return 45
    }

    private static func processEnvironment(for executable: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let executableDirectory = URL(fileURLWithPath: executable).deletingLastPathComponent().path
        let defaultPathEntries = [
            executableDirectory,
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        environment["PATH"] = Array(NSOrderedSet(array: defaultPathEntries))
            .compactMap { $0 as? String }
            .joined(separator: ":")
        return environment
    }
}

private enum AppUpdateError: LocalizedError {
    case lookupFailed(String)
    case malformedURL
    case insecureURL(String)

    var errorDescription: String? {
        switch self {
        case .lookupFailed(let message):
            return message
        case .malformedURL:
            return "SK Mole could not construct the update lookup URL."
        case .insecureURL(let value):
            return "SK Mole blocked an insecure update source: \(value)"
        }
    }
}

private struct AppStoreLookupPayload: Decodable {
    let results: [AppStoreLookupResult]
}

private struct AppStoreLookupResult: Decodable {
    let version: String?
    let trackViewUrl: String?
    let artistViewUrl: String?
    let releaseNotes: String?
    let currentVersionReleaseDateRaw: String?

    var trackViewURL: URL? {
        guard let trackViewUrl else { return nil }
        return URL(string: trackViewUrl)
    }

    var artistViewURL: URL? {
        guard let artistViewUrl else { return nil }
        return URL(string: artistViewUrl)
    }

    var currentVersionReleaseDate: Date? {
        guard let currentVersionReleaseDateRaw else { return nil }
        return ISO8601DateFormatter().date(from: currentVersionReleaseDateRaw)
    }

    enum CodingKeys: String, CodingKey {
        case version
        case trackViewUrl
        case artistViewUrl
        case releaseNotes
        case currentVersionReleaseDateRaw = "currentVersionReleaseDate"
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String?
    let name: String?
    let htmlUrl: String?
    let body: String?
    let publishedAtRaw: String?
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlUrl = "html_url"
        case body
        case publishedAtRaw = "published_at"
        case assets
    }

    var htmlURL: URL? {
        guard let htmlUrl else { return nil }
        return URL(string: htmlUrl)
    }

    var publishedAt: Date? {
        guard let publishedAtRaw else { return nil }
        return ISO8601DateFormatter().date(from: publishedAtRaw)
    }

    var preferredInstallerAsset: GitHubReleaseAsset? {
        assets.first { $0.isDiskImage }
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let size: Int?
    let browserDownloadUrl: String?

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case browserDownloadUrl = "browser_download_url"
    }

    var downloadURL: URL? {
        guard let browserDownloadUrl else { return nil }
        return URL(string: browserDownloadUrl)
    }

    var isDiskImage: Bool {
        name.lowercased().hasSuffix(".dmg")
    }
}

private struct SparkleFeedSummary {
    let latestVersion: String?
    let itemURL: URL?
    let releaseNotesURL: URL?
    let fullReleaseNotesURL: URL?
    let downloadURL: URL?
    let embeddedReleaseNotes: String?
}

private final class SparkleAppcastParser: NSObject, XMLParserDelegate {
    private struct Item {
        var itemURL: URL?
        var releaseNotesURL: URL?
        var fullReleaseNotesURL: URL?
        var downloadURL: URL?
        var shortVersion: String?
        var version: String?
        var itemDescription: String?
    }

    private let baseURL: URL
    private var currentItem: Item?
    private var parsedItem: Item?
    private var currentElement: String?
    private var currentText = ""
    private let maximumElementTextLength = 16_384

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func parse(data: Data) throws -> SparkleFeedSummary {
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self

        guard parser.parse() else {
            throw parser.parserError ?? AppUpdateError.lookupFailed("The Sparkle appcast could not be parsed.")
        }

        let resolved = parsedItem ?? currentItem
        return SparkleFeedSummary(
            latestVersion: resolved?.shortVersion ?? resolved?.version,
            itemURL: resolved?.itemURL,
            releaseNotesURL: resolved?.releaseNotesURL,
            fullReleaseNotesURL: resolved?.fullReleaseNotesURL,
            downloadURL: resolved?.downloadURL,
            embeddedReleaseNotes: resolved?.itemDescription
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentText = ""

        if elementName == "item" {
            currentItem = Item()
            return
        }

        guard currentItem != nil else {
            return
        }

        if elementName == "enclosure" {
            if let download = resolvedSecureURL(attributeDict["url"]) {
                currentItem?.downloadURL = download
            }
            if let shortVersion = attributeDict["sparkle:shortVersionString"] ?? attributeDict["shortVersionString"] {
                currentItem?.shortVersion = shortVersion
            }
            if let version = attributeDict["sparkle:version"] ?? attributeDict["version"] {
                currentItem?.version = version
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentText.count < maximumElementTextLength else {
            return
        }

        let remaining = maximumElementTextLength - currentText.count
        currentText += string.prefix(remaining)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if currentItem != nil {
            switch elementName {
            case "link":
                if currentItem?.itemURL == nil, let url = resolvedSecureURL(text) {
                    currentItem?.itemURL = url
                }
            case "sparkle:releaseNotesLink", "releaseNotesLink":
                if let url = resolvedSecureURL(text) {
                    currentItem?.releaseNotesURL = url
                }
            case "sparkle:fullReleaseNotesLink", "fullReleaseNotesLink":
                if let url = resolvedSecureURL(text) {
                    currentItem?.fullReleaseNotesURL = url
                }
            case "sparkle:shortVersionString", "shortVersionString":
                if !text.isEmpty {
                    currentItem?.shortVersion = text
                }
            case "sparkle:version", "version":
                if !text.isEmpty {
                    currentItem?.version = text
                }
            case "description":
                if !text.isEmpty {
                    currentItem?.itemDescription = text
                }
            case "item":
                if parsedItem == nil {
                    parsedItem = currentItem
                }
                currentItem = nil
            default:
                break
            }
        }

        currentElement = nil
        currentText = ""
    }

    private func resolvedSecureURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else {
            return nil
        }

        let resolved = URL(string: value, relativeTo: baseURL)?.absoluteURL
        return resolved?.scheme == "https" ? resolved : nil
    }
}

private struct ProcessResult {
    let output: String
    let terminationStatus: Int32
}

private extension URLComponents {
    func requireURL() throws -> URL {
        guard let url else {
            throw AppUpdateError.malformedURL
        }

        return url
    }
}
