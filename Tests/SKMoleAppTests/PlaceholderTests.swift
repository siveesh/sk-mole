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
    #expect(StartupPreference.quarantine.resolve(lastSelection: .cleanup) == .quarantine)
    #expect(StartupPreference.rememberLast.resolve(lastSelection: .storage) == .storage)
    #expect(StartupPreference.rememberLast.resolve(lastSelection: nil) == .dashboard)
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

@Test func gitHubCLICommandsRemainStable() async throws {
    #expect(GitHubCLIStatus.installCommand == "brew install gh")
    #expect(GitHubCLIStatus.authCommand == "gh auth login --web --git-protocol https")
    #expect(GitHubCLIStatus.personalAccessTokenURL.absoluteString.contains("personal-access-tokens"))
}

@Test func featuredHomebrewCatalogIsExpanded() async throws {
    #expect(HomebrewPackageSearchResult.featured.count >= 30)
    #expect(HomebrewPackageSearchResult.featured.contains(where: { $0.token == "gh" }))
    #expect(HomebrewPackageSearchResult.featured.contains(where: { $0.token == "rectangle" && $0.bundleIdentifier == "com.knollsoft.Rectangle" }))
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
