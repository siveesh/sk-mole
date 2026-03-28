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
    #expect(StartupPreference.rememberLast.resolve(lastSelection: .storage) == .storage)
    #expect(StartupPreference.rememberLast.resolve(lastSelection: nil) == .dashboard)
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
