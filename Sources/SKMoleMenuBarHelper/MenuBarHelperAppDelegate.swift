import AppKit
import SwiftUI
import SKMoleShared

@MainActor
final class MenuBarHelperAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let sampler = MenuBarHelperSampler()
    private let settingsStore = MenuBarCompanionSettingsStore()
    private let alertEvaluator = MenuBarAlertEvaluator()
    private let updateStatusStore = AppUpdateStatusStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let contentModel = MenuBarCompanionContentModel()
    private let popoverWidth: CGFloat = 336
    private var cachedSettings = MenuBarCompanionSettings.default
    private var lastSettingsLoadDate = Date.distantPast
    private var lastUpdateSnapshotLoadDate = Date.distantPast
    private let settingsReloadInterval: TimeInterval = 5
    private let updateSnapshotReloadInterval: TimeInterval = 15

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        cachedSettings = settingsStore.load()
        lastSettingsLoadDate = .now
        refreshSharedUpdateSummary(force: true)

        sampler.start { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.apply(snapshot: snapshot)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        sampler.stop()
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = NSImage(systemSymbolName: "aqi.medium", accessibilityDescription: "SK Mole Companion")
        button.imagePosition = .imageOnly
        button.title = ""
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPopover() {
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: popoverWidth, height: preferredPopoverHeight(anchor: nil))
        popover.contentViewController = NSHostingController(
            rootView: MenuBarCompanionPopoverView(
                model: contentModel,
                openMainApp: { [weak self] in self?.openMainApp() },
                openUpdates: { [weak self] in self?.openUpdates() },
                openNetwork: { [weak self] in self?.openNetworkInspector() },
                openProcesses: { [weak self] in self?.openProcesses() },
                openSmartCare: { [weak self] in self?.openSmartCare() },
                openPrivacySecurity: { [weak self] in self?.openPrivacySecurity() },
                quitMainApp: { [weak self] in self?.quitMainApp() },
                quitCompanion: { [weak self] in self?.quitCompanion() }
            )
        )
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        cachedSettings = settingsStore.load()
        lastSettingsLoadDate = .now
        refreshSharedUpdateSummary(force: true)

        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
            sampler.setPopoverVisible(false)
        } else {
            popover.contentSize = NSSize(width: popoverWidth, height: preferredPopoverHeight(anchor: button.window?.screen))
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            sampler.setPopoverVisible(true)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        sampler.setPopoverVisible(false)
    }

    private func preferredPopoverHeight(anchor screen: NSScreen?) -> CGFloat {
        let visibleHeight = (screen ?? NSScreen.main)?.visibleFrame.height ?? 720
        return max(280, min(640, visibleHeight - 80))
    }

    private func apply(snapshot: MenuBarSnapshot) {
        let settings = loadSettingsIfNeeded()
        let activeAlerts = alertEvaluator.evaluate(snapshot: snapshot, settings: settings)
        refreshSharedUpdateSummary()

        contentModel.snapshot = snapshot
        contentModel.activeAlerts = activeAlerts
        applyStatusPresentation(
            snapshot: snapshot,
            activeAlerts: activeAlerts,
            updateSnapshot: contentModel.updateSnapshot,
            settings: settings
        )
    }

    private func refreshSharedUpdateSummary(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastUpdateSnapshotLoadDate) >= updateSnapshotReloadInterval else {
            return
        }

        contentModel.updateSnapshot = updateStatusStore.load()
        lastUpdateSnapshotLoadDate = now
    }

    private func loadSettingsIfNeeded() -> MenuBarCompanionSettings {
        let now = Date()
        guard now.timeIntervalSince(lastSettingsLoadDate) >= settingsReloadInterval else {
            return cachedSettings
        }

        cachedSettings = settingsStore.load()
        lastSettingsLoadDate = now
        return cachedSettings
    }

    private func applyStatusPresentation(
        snapshot: MenuBarSnapshot,
        activeAlerts: [MenuBarActiveAlert],
        updateSnapshot: AppUpdateStatusSnapshot?,
        settings: MenuBarCompanionSettings
    ) {
        guard let button = statusItem.button else { return }

        if !activeAlerts.isEmpty {
            button.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "SK Mole alerts")
            button.toolTip = activeAlerts.map(\.title).joined(separator: "\n")
            return
        }

        if let updateSnapshot, updateSnapshot.actionableCount > 0 {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath.circle.fill", accessibilityDescription: "SK Mole updates")
        } else {
            button.image = NSImage(systemSymbolName: statusSymbol(for: settings.visibleStatusMetrics.first ?? .cpu), accessibilityDescription: "SK Mole Companion")
        }

        let metrics = settings.visibleStatusMetrics.isEmpty ? [.cpu] : settings.visibleStatusMetrics
        var tooltipParts = metrics.map { combinedMetricText(for: $0, snapshot: snapshot) }
        if let updateSnapshot {
            tooltipParts.append("Updates \(updateSnapshot.actionableCount) actionable")
        }
        button.toolTip = tooltipParts.joined(separator: " • ")
    }

    private func combinedMetricText(for metric: MenuBarStatusMetric, snapshot: MenuBarSnapshot) -> String {
        switch metric {
        case .cpu:
            return "CPU \(Int((snapshot.cpuUsage * 100).rounded()))%"
        case .memory:
            return "MEM \(Int((snapshot.memoryUsage * 100).rounded()))%"
        case .network:
            return "NET ↓\(MenuBarHelperFormatting.formatRate(snapshot.downloadRate))"
        case .thermal:
            return "THERM \(thermalTitle(for: snapshot.thermalStateLevel))"
        case .pressure:
            return "PRESS \(pressureTitle(for: snapshot.memoryPressureLevel))"
        case .battery:
            if let batteryLevel = snapshot.batteryLevel {
                return "BAT \(Int((batteryLevel * 100).rounded()))%"
            }
            return "BAT AC"
        case .diskFree:
            return "FREE \(Int((snapshot.diskFreeRatio * 100).rounded()))%"
        }
    }

    private func statusSymbol(for metric: MenuBarStatusMetric) -> String {
        switch metric {
        case .cpu:
            return "cpu"
        case .memory:
            return "memorychip"
        case .network:
            return "arrow.left.and.right.circle"
        case .thermal:
            return "thermometer.medium"
        case .pressure:
            return "waveform.path.ecg"
        case .battery:
            return "battery.100"
        case .diskFree:
            return "internaldrive"
        }
    }

    private func pressureTitle(for level: Int) -> String {
        SharedMemoryPressureLevel(rawValue: level)?.title ?? "Stable"
    }

    private func thermalTitle(for level: Int) -> String {
        switch level {
        case 3:
            return "Critical"
        case 2:
            return "Serious"
        case 1:
            return "Fair"
        default:
            return "Nominal"
        }
    }

    private func open(sectionSlug: String) {
        if let deepLink = URL(string: "\(MenuBarHelperConstants.mainAppURLScheme)://section/\(sectionSlug)"),
           NSWorkspace.shared.open(deepLink) {
            return
        }

        openMainApp()
    }

    @objc
    private func openMainApp() {
        guard let mainAppURL = mainApplicationURL() else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.addsToRecentItems = false

        NSWorkspace.shared.openApplication(at: mainAppURL, configuration: configuration)
    }

    @objc
    private func openUpdates() {
        open(sectionSlug: "updates")
    }

    @objc
    private func openNetworkInspector() {
        open(sectionSlug: "network")
    }

    @objc
    private func openProcesses() {
        open(sectionSlug: "processes")
    }

    @objc
    private func openSmartCare() {
        open(sectionSlug: "smart-care")
    }

    @objc
    private func openPrivacySecurity() {
        if let privacySecurityURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {
            NSWorkspace.shared.open(privacySecurityURL)
        }
    }

    @objc
    private func quitMainApp() {
        NSRunningApplication.runningApplications(withBundleIdentifier: MenuBarHelperConstants.mainAppBundleIdentifier).forEach {
            $0.terminate()
        }
    }

    @objc
    private func quitCompanion() {
        NSApp.terminate(nil)
    }

    private func mainApplicationURL() -> URL? {
        let helperBundleURL = Bundle.main.bundleURL
        return helperBundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
