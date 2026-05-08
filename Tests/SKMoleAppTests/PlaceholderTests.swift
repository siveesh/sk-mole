import Foundation
import Testing
@testable import SKMoleApp
import SKMoleShared

@Test func byteFormattingUsesUnits() async throws {
    #expect(ByteFormatting.format(1_024 * 1_024).contains("MB"))
}

@Test func privilegedTaskCatalogIsStable() async throws {
    #expect(PrivilegedMaintenanceTask.allCases.count == 3)
    #expect(PrivilegedMaintenanceTask.flushDNSCache.title.contains("DNS"))
    #expect(PrivilegedMaintenanceTask.freePurgeableSpace.title.contains("purgeable"))
}

@Test func startupPreferenceResolvesExpectedSection() async throws {
    #expect(StartupPreference.dashboard.resolve(lastSelection: .cleanup) == .dashboard)
    #expect(StartupPreference.homebrew.resolve(lastSelection: .cleanup) == .homebrew)
    #expect(StartupPreference.fileIntelligence.resolve(lastSelection: .cleanup) == .fileIntelligence)
    #expect(StartupPreference.processes.resolve(lastSelection: .cleanup) == .processes)
    #expect(StartupPreference.quarantine.resolve(lastSelection: .cleanup) == .quarantine)
    #expect(StartupPreference.orphans.resolve(lastSelection: .cleanup) == .orphans)
    #expect(StartupPreference.rememberLast.resolve(lastSelection: .storage) == .storage)
    #expect(StartupPreference.rememberLast.resolve(lastSelection: nil) == .dashboard)
}

@Test func orphanScannerNormalizesAndMatchesKnownTokens() async throws {
    #expect(OrphanedFileScanner.matchToken(for: "group.com.example.app") == "com.example.app")
    #expect(
        OrphanedFileScanner.matchesInstalledApp(
            token: "com.example.app.helper",
            bundleIdentifiers: ["com.example.app"],
            appNameTokens: []
        )
    )
    #expect(
        !OrphanedFileScanner.matchesInstalledApp(
            token: "com.example.oldapp",
            bundleIdentifiers: ["com.example.currentapp"],
            appNameTokens: ["currentapp"]
        )
    )
}

@Test func orphanSidebarSlugResolves() async throws {
    #expect(SidebarSection(urlSlug: "orphans") == .orphans)
    #expect(SidebarSection(urlSlug: "leftovers") == .orphans)
    #expect(SidebarSection(urlSlug: "magika") == .fileIntelligence)
    #expect(SidebarSection(urlSlug: "process-inspector") == .processes)
}

@Test func uninstallSensitivityCatalogRemainsStable() async throws {
    #expect(UninstallSensitivityLevel.allCases.map(\.rawValue) == ["strict", "enhanced", "deep"])
    #expect(UninstallSensitivityLevel.deep.subtitle.contains("wider"))
}

@Test func scheduledMaintenanceFormatMapsToExporter() async throws {
    #expect(ScheduledMaintenanceExportFormat.markdown.pluginID == .overviewMarkdown)
    #expect(ScheduledMaintenanceExportFormat.json.pluginID == .dryRunJSON)
    #expect(ScheduledMaintenanceInterval.daily.minimumSpacing == 86_400)
}

@Test func homebrewCommandStringsReflectPackageKind() async throws {
    let formulaReference = HomebrewPackageReference(token: "wget", kind: .formula)
    let caskReference = HomebrewPackageReference(token: "iterm2", kind: .cask)

    #expect(HomebrewPackageKind.formula.installCommand(for: formulaReference.token) == "brew install wget")
    #expect(HomebrewPackageKind.formula.uninstallCommand(for: formulaReference.token) == "brew uninstall wget")
    #expect(HomebrewPackageKind.cask.installCommand(for: caskReference.token) == "brew install --cask iterm2")
    #expect(HomebrewPackageKind.cask.upgradeCommand(for: caskReference.token) == "brew upgrade --cask iterm2")
}

@Test func homebrewMaintenanceCatalogMatchesExpectedCommands() async throws {
    #expect(HomebrewMaintenanceAction.updateMetadata.command == "brew update")
    #expect(HomebrewMaintenanceAction.upgradeAll.command == "brew upgrade")
    #expect(HomebrewMaintenanceAction.cleanup.command == "brew cleanup --prune=all")
    #expect(HomebrewMaintenanceAction.doctor.command == "brew doctor")
}

@Test func homebrewDoctorPathsOnlyAllowSupportedDylibs() async throws {
    let supported = HomebrewDoctorIssuePath(path: "/usr/local/lib/libbroken.dylib", note: nil)
    let unsupportedExtension = HomebrewDoctorIssuePath(path: "/usr/local/lib/libbroken.a", note: nil)
    let unsupportedRoot = HomebrewDoctorIssuePath(path: "/System/Library/libbroken.dylib", note: nil)

    #expect(supported.canDelete)
    #expect(!unsupportedExtension.canDelete)
    #expect(!unsupportedRoot.canDelete)
}

@Test func homebrewSanitizerExtractsJSONObjectEnvelope() async throws {
    let raw = """
    Warning: something noisy before JSON
    {\"formulae\":[],\"casks\":[]}
    """

    #expect(HomebrewService.sanitizeJSONObjectEnvelope(from: raw) == #"{"formulae":[],"casks":[]}"#)
}

@Test func homebrewInventoryPreservesProvidedStatusWhenExecutableIsMissing() async throws {
    let service = HomebrewService()
    let status = HomebrewStatus(executablePath: nil, version: nil, prefix: nil)

    let inventory = try await service.loadInventory(using: status)

    #expect(inventory.status == status)
    #expect(inventory.installedPackages.isEmpty)
    #expect(inventory.services.isEmpty)
}

@Test func gitHubCLICommandsRemainStable() async throws {
    #expect(GitHubCLIStatus.installCommand == "brew install gh")
    #expect(GitHubCLIStatus.authCommand == "gh auth login --web --git-protocol https")
    #expect(GitHubCLIStatus.personalAccessTokenURL.absoluteString.contains("personal-access-tokens"))
}

@Test func featuredHomebrewCatalogIsExpanded() async throws {
    #expect(HomebrewPackageSearchResult.featured.count >= 30)
    #expect(HomebrewPackageSearchResult.featured.contains(where: { $0.token == "gh" }))
    #expect(HomebrewPackageSearchResult.featured.contains(where: { $0.token == "magika" }))
    #expect(HomebrewPackageSearchResult.featured.contains(where: { $0.token == "rectangle" && $0.bundleIdentifier == "com.knollsoft.Rectangle" }))
}

@Test func magikaSanitizerExtractsJSONArrayEnvelope() async throws {
    let raw = """
    noisy preface
    [{"path":"/tmp/demo.txt","result":{"status":"ok","value":{"dl":{"description":"Plain text","extensions":["txt"],"group":"text","is_text":true,"label":"txt","mime_type":"text/plain"},"output":{"description":"Plain text","extensions":["txt"],"group":"text","is_text":true,"label":"txt","mime_type":"text/plain"},"score":0.9}}}]
    """

    #expect(MagikaService.sanitizeJSONArrayEnvelope(from: raw).hasPrefix("[{"))
}

@Test func quarantinedApplicationBuildsExpectedXattrCommand() async throws {
    let app = QuarantinedApplication(
        name: "Test App",
        bundleIdentifier: "com.example.test",
        url: URL(fileURLWithPath: "/Applications/Test App.app"),
        sizeBytes: 1_024,
        quarantineValue: "0081;12345678;Safari;",
        signatureStatus: .unsigned,
        lastModified: nil
    )

    #expect(app.xattrCommand.contains("/usr/bin/xattr -d com.apple.quarantine"))
    #expect(app.xattrCommand.contains("\"/Applications/Test App.app\""))
}

@Test func powerSnapshotSummaryIncludesChargingAndLowPowerMode() async throws {
    let snapshot = PowerSourceSnapshot(
        source: "Battery Power",
        batteryLevel: 0.82,
        isCharging: true,
        timeRemainingMinutes: 45,
        lowPowerMode: true
    )

    #expect(snapshot.summary.contains("Battery"))
    #expect(snapshot.summary.contains("82%"))
    #expect(snapshot.summary.contains("Charging"))
    #expect(snapshot.summary.contains("Low Power"))
}

@Test func menuBarMemoryAlertDefaultIsSeventyFivePercent() async throws {
    let memoryRule = try #require(MenuBarAlertRule.defaults.first(where: { $0.id == "memory-usage" }))
    #expect(memoryRule.metric == .memoryUsage)
    #expect(memoryRule.threshold == 0.75)
}

@Test func menuBarMemoryPressureAlertDefaultsToHigh() async throws {
    let pressureRule = try #require(MenuBarAlertRule.defaults.first(where: { $0.id == "memory-pressure" }))
    #expect(pressureRule.metric == .memoryPressure)
    #expect(pressureRule.threshold == 2)
}

@Test func discreteMenuBarThresholdOptionsRemainStable() async throws {
    #expect(MenuBarAlertMetric.memoryPressure.discreteThresholdOptions.map(\.title) == ["Elevated", "High"])
    #expect(MenuBarAlertMetric.thermalState.discreteThresholdOptions.map(\.title) == ["Fair", "Serious", "Critical"])
}

@Test func sharedMemoryPressureClassificationRemainsConservative() async throws {
    let sixteenGB = UInt64(16 * 1_024 * 1_024 * 1_024)
    let gigabyte = UInt64(1_024 * 1_024 * 1_024)

    #expect(
        SharedMemoryPressureLevel.classify(
            available: UInt64(Double(sixteenGB) * 0.14),
            total: sixteenGB,
            swapUsed: 0,
            compressed: gigabyte / 2
        ) == .elevated
    )

    #expect(
        SharedMemoryPressureLevel.classify(
            available: UInt64(Double(sixteenGB) * 0.04),
            total: sixteenGB,
            swapUsed: 0,
            compressed: gigabyte / 2
        ) == .high
    )
}
