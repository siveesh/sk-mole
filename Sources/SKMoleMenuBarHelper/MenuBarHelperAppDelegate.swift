import AppKit
import SKMoleShared

@MainActor
final class MenuBarHelperAppDelegate: NSObject, NSApplicationDelegate {
    private let sampler = MenuBarHelperSampler()
    private let settingsStore = MenuBarCompanionSettingsStore()
    private let alertEvaluator = MenuBarAlertEvaluator()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let alertsHeaderItem = NSMenuItem(title: "No active alerts", action: nil, keyEquivalent: "")
    private let sensorsHeaderItem = NSMenuItem(title: "Live sensors", action: nil, keyEquivalent: "")
    private let cpuItem = NSMenuItem(title: "CPU: --", action: nil, keyEquivalent: "")
    private let memoryItem = NSMenuItem(title: "Memory: --", action: nil, keyEquivalent: "")
    private let pressureItem = NSMenuItem(title: "Memory Pressure: --", action: nil, keyEquivalent: "")
    private let thermalItem = NSMenuItem(title: "Thermal: --", action: nil, keyEquivalent: "")
    private let diskItem = NSMenuItem(title: "Disk Free: --", action: nil, keyEquivalent: "")
    private let networkItem = NSMenuItem(title: "Network: --", action: nil, keyEquivalent: "")
    private let powerItem = NSMenuItem(title: "Power: --", action: nil, keyEquivalent: "")
    private let processItem = NSMenuItem(title: "Top Process: --", action: nil, keyEquivalent: "")
    private var alertMenuItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupMenu()

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
        button.font = .systemFont(ofSize: 12, weight: .semibold)
    }

    private func setupMenu() {
        [alertsHeaderItem, sensorsHeaderItem].forEach { $0.isEnabled = false }
        [cpuItem, memoryItem, pressureItem, thermalItem, diskItem, networkItem, powerItem, processItem].forEach {
            $0.isEnabled = false
        }

        menu.addItem(alertsHeaderItem)
        menu.addItem(.separator())
        menu.addItem(sensorsHeaderItem)
        [cpuItem, memoryItem, pressureItem, thermalItem, diskItem, networkItem, powerItem, processItem].forEach(menu.addItem(_:))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open SK Mole", action: #selector(openMainApp), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Open Network Inspector", action: #selector(openNetworkInspector), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "Open Smart Care", action: #selector(openSmartCare), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Open Privacy & Security", action: #selector(openPrivacySecurity), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SK Mole", action: #selector(quitMainApp), keyEquivalent: "q"))
        menu.addItem(NSMenuItem(title: "Quit Companion", action: #selector(quitCompanion), keyEquivalent: ""))

        menu.items.forEach { item in
            item.target = self
        }

        statusItem.menu = menu
    }

    private func apply(snapshot: MenuBarSnapshot) {
        let settings = settingsStore.load()
        let activeAlerts = alertEvaluator.evaluate(snapshot: snapshot, settings: settings)
        refreshAlertMenu(activeAlerts)
        applyStatusPresentation(snapshot: snapshot, settings: settings, activeAlerts: activeAlerts)

        cpuItem.title = "CPU: \(Int((snapshot.cpuUsage * 100).rounded()))%"
        memoryItem.title = "Memory: \(MenuBarHelperFormatting.formatBytes(snapshot.memoryUsed)) of \(MenuBarHelperFormatting.formatBytes(snapshot.memoryTotal)) • \(Int((snapshot.memoryUsage * 100).rounded()))%"
        pressureItem.title = "Memory Pressure: \(pressureTitle(for: snapshot.memoryPressureLevel))"
        thermalItem.title = "Thermal: \(thermalTitle(for: snapshot.thermalStateLevel))"
        diskItem.title = "Disk Free: \(MenuBarHelperFormatting.formatBytes(snapshot.diskFreeBytes)) • \(Int((snapshot.diskFreeRatio * 100).rounded()))% free"
        networkItem.title = "Network: ↓ \(MenuBarHelperFormatting.formatRate(snapshot.downloadRate)) ↑ \(MenuBarHelperFormatting.formatRate(snapshot.uploadRate))"
        powerItem.title = "Power: \(snapshot.powerSummary ?? "Unavailable")"

        if let topProcessName = snapshot.topProcessName, let topProcessCPU = snapshot.topProcessCPU {
            let memorySuffix = snapshot.topProcessMemoryBytes.map { " • \(MenuBarHelperFormatting.formatBytes($0))" } ?? ""
            processItem.title = "Top Process: \(topProcessName) • \(String(format: "%.1f%% CPU", topProcessCPU))\(memorySuffix)"
        } else {
            processItem.title = "Top Process: Sampling..."
        }
    }

    private func applyStatusPresentation(
        snapshot: MenuBarSnapshot,
        settings: MenuBarCompanionSettings,
        activeAlerts: [MenuBarActiveAlert]
    ) {
        guard let button = statusItem.button else { return }

        if activeAlerts.isEmpty {
            let metrics = settings.visibleStatusMetrics.isEmpty ? [.cpu] : settings.visibleStatusMetrics
            button.image = NSImage(systemSymbolName: statusSymbol(for: metrics.first ?? .cpu), accessibilityDescription: "SK Mole Companion")
            button.title = ""
            button.toolTip = metrics
                .map { combinedMetricText(for: $0, snapshot: snapshot) }
                .joined(separator: " • ")
        } else {
            button.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "SK Mole alerts")
            button.title = ""
            button.toolTip = activeAlerts.map(\.title).joined(separator: "\n")
        }
    }

    private func refreshAlertMenu(_ activeAlerts: [MenuBarActiveAlert]) {
        alertMenuItems.forEach(menu.removeItem(_:))
        alertMenuItems.removeAll()

        if activeAlerts.isEmpty {
            alertsHeaderItem.title = "No active alerts"
            return
        }

        alertsHeaderItem.title = "\(activeAlerts.count) active alert\(activeAlerts.count == 1 ? "" : "s")"

        for (index, alert) in activeAlerts.enumerated() {
            let item = NSMenuItem(
                title: "\(alert.title): \(alert.detail)",
                action: #selector(openSmartCare),
                keyEquivalent: ""
            )
            item.image = NSImage(systemSymbolName: alert.rule.metric.symbol, accessibilityDescription: alert.title)
            item.target = self
            menu.insertItem(item, at: 1 + index)
            alertMenuItems.append(item)
        }
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
        switch level {
        case 2:
            return "High"
        case 1:
            return "Elevated"
        default:
            return "Stable"
        }
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
    private func openNetworkInspector() {
        if let deepLink = URL(string: "\(MenuBarHelperConstants.mainAppURLScheme)://section/network"),
           NSWorkspace.shared.open(deepLink) {
            return
        }

        openMainApp()
    }

    @objc
    private func openSmartCare() {
        if let deepLink = URL(string: "\(MenuBarHelperConstants.mainAppURLScheme)://section/smart-care"),
           NSWorkspace.shared.open(deepLink) {
            return
        }

        openMainApp()
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
