import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var monitor: SystemMonitorStore
    @Environment(\.openSettings) private var openSettings

    init(model: AppModel) {
        self._model = ObservedObject(wrappedValue: model)
        self._monitor = ObservedObject(wrappedValue: model.monitorStore)
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - 40, 320)

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    hero
                    metricsGrid(for: contentWidth)
                    insightBoards(for: contentWidth)
                    operationsBoards(for: contentWidth)
                    topProcessesSection
                }
                .padding(20)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("System status at a glance")
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Text("Live health, update awareness, cleanup pressure, and quick paths into the heavier tools.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 18)

                HStack(spacing: 10) {
                    heroStat(
                        title: "Smart Care",
                        value: "\(model.smartCareScore)",
                        subtitle: "\(model.recommendedActions.count) recommendations",
                        tint: AppPalette.accent
                    )

                    heroStat(
                        title: "Updates",
                        value: "\(model.activeAvailableUpdateItems.count)",
                        subtitle: model.activeAvailableUpdateItems.filter(\.canAutoInstall).isEmpty
                            ? "manual review"
                            : "\(model.activeAvailableUpdateItems.filter(\.canAutoInstall).count) automatic",
                        tint: AppPalette.sky
                    )

                    heroStat(
                        title: "Cleanup",
                        value: ByteFormatting.format(model.cleanupBytes),
                        subtitle: model.cleanupBusy ? "scanning..." : "reclaimable",
                        tint: AppPalette.amber
                    )
                }
            }

            HStack(spacing: 10) {
                chip("Companion optional", tint: AppPalette.accent)
                chip("Scans are lazy and reusable", tint: AppPalette.sky)
                chip("Ignored / deferred updates supported", tint: AppPalette.amber)
                chip("Full Disk Access guidance built in", tint: AppPalette.rose)
            }

            HStack(spacing: 10) {
                dashboardAction("Refresh Current", symbol: "arrow.clockwise") {
                    Task { await model.refreshCurrentSelection() }
                }

                dashboardAction("Updates", symbol: "arrow.triangle.2.circlepath.circle") {
                    model.open(section: .updates)
                }

                dashboardAction("Smart Care", symbol: "sparkles.rectangle.stack.fill") {
                    model.open(section: .smartCare)
                }

                dashboardAction("Network", symbol: "network") {
                    model.open(section: .network)
                }

                dashboardAction("Processes", symbol: "list.bullet.rectangle.portrait") {
                    model.open(section: .processes)
                }

                dashboardAction("Settings", symbol: "gearshape") {
                    openSettings()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppPalette.heroGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
        )
    }

    private func metricsGrid(for width: CGFloat) -> some View {
        LazyVGrid(columns: metricColumns(for: width), alignment: .leading, spacing: 16) {
            MetricCard(
                title: "CPU",
                value: "\(Int((monitor.metrics.cpuUsage * 100).rounded()))%",
                detail: "\(max(monitor.metrics.perCoreUsage.count, 1)) cores sampled once per second",
                symbol: "cpu",
                tint: AppPalette.accent,
                progress: monitor.metrics.cpuUsage
            )

            MetricCard(
                title: "Memory",
                value: ByteFormatting.format(monitor.metrics.memoryUsed),
                detail: "of \(ByteFormatting.format(monitor.metrics.memoryTotal)) in use",
                symbol: "memorychip",
                tint: AppPalette.sky,
                progress: monitor.metrics.memoryUsage
            )

            MetricCard(
                title: "Pressure",
                value: monitor.metrics.memoryPressure.title,
                detail: "\(ByteFormatting.format(monitor.metrics.memoryCompressed)) compressed • \(ByteFormatting.format(monitor.metrics.swapUsed)) swap",
                symbol: monitor.metrics.memoryPressure.symbol,
                tint: pressureTint,
                progress: pressureProgress
            )

            MetricCard(
                title: "Thermal",
                value: monitor.metrics.thermalState.title,
                detail: monitor.metrics.powerSource?.summary ?? "Public thermal headroom from macOS",
                symbol: "thermometer.medium",
                tint: thermalTint,
                progress: thermalProgress
            )

            MetricCard(
                title: "Disk",
                value: ByteFormatting.format(monitor.metrics.diskUsed),
                detail: "of \(ByteFormatting.format(monitor.metrics.diskTotal)) occupied",
                symbol: "internaldrive",
                tint: AppPalette.rose,
                progress: monitor.metrics.diskUsage
            )

            MetricCard(
                title: "Down",
                value: ByteFormatting.formatRate(monitor.metrics.networkDownloadRate),
                detail: "current inbound throughput",
                symbol: "arrow.down.circle",
                tint: AppPalette.sky,
                progress: nil
            )

            MetricCard(
                title: "Up",
                value: ByteFormatting.formatRate(monitor.metrics.networkUploadRate),
                detail: "current outbound throughput",
                symbol: "arrow.up.circle",
                tint: AppPalette.accent,
                progress: nil
            )

            MetricCard(
                title: "Power",
                value: monitor.metrics.powerSource?.sourceTitle ?? "Unavailable",
                detail: monitor.metrics.powerSource?.summary ?? "No public power source details on this Mac",
                symbol: powerSymbol,
                tint: AppPalette.mint,
                progress: monitor.metrics.powerSource?.batteryLevel
            )
        }
    }

    private func insightBoards(for width: CGFloat) -> some View {
        LazyVGrid(columns: boardColumns(for: width), alignment: .leading, spacing: 16) {
            historyPanel(
                title: "CPU History",
                subtitle: "Recent total CPU load across all cores.",
                value: "\(Int((monitor.metrics.cpuUsage * 100).rounded()))%",
                tint: AppPalette.accent,
                points: monitor.cpuHistory
            )

            historyPanel(
                title: "Memory History",
                subtitle: "Resident memory use as a share of physical RAM.",
                value: "\(Int((monitor.metrics.memoryUsage * 100).rounded()))%",
                tint: AppPalette.sky,
                points: monitor.memoryHistory
            )

            DashboardPanel(
                title: "Network History",
                subtitle: "Live throughput with a quick path into the on-demand connection inspector.",
                symbol: "arrow.left.and.right.circle"
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        statHeader("Down", ByteFormatting.formatRate(monitor.metrics.networkDownloadRate), AppPalette.sky)
                        HistorySparkline(points: monitor.downloadHistory, tint: AppPalette.sky)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        statHeader("Up", ByteFormatting.formatRate(monitor.metrics.networkUploadRate), AppPalette.accent)
                        HistorySparkline(points: monitor.uploadHistory, tint: AppPalette.accent)
                    }

                    Button("Open Network Inspector") {
                        model.open(section: .network)
                    }
                    .buttonStyle(.bordered)
                }
            }

            updatePulsePanel

            DashboardPanel(
                title: "Pressure and Thermal",
                subtitle: "Public macOS headroom signals presented as a compact watchboard instead of one aggregate warning.",
                symbol: "waveform.path.ecg"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    monitoringFact(
                        title: "Memory pressure",
                        value: monitor.metrics.memoryPressure.title,
                        detail: "\(ByteFormatting.format(monitor.metrics.memoryWired)) wired • \(ByteFormatting.format(monitor.metrics.memoryCached)) cached",
                        tint: pressureTint
                    )

                    monitoringFact(
                        title: "Thermal state",
                        value: monitor.metrics.thermalState.title,
                        detail: "Sampler cadence stays light even while the dashboard is open",
                        tint: thermalTint
                    )
                }
            }

            DashboardPanel(
                title: "Per-Core CPU",
                subtitle: "Spot uneven bursts and single-core bottlenecks without leaving the main dashboard.",
                symbol: "square.split.2x2"
            ) {
                PerCoreUsageGrid(usage: monitor.metrics.perCoreUsage)
            }
        }
    }

    private func operationsBoards(for width: CGFloat) -> some View {
        LazyVGrid(columns: boardColumns(for: width), alignment: .leading, spacing: 16) {
            DashboardPanel(
                title: "Smart Care",
                subtitle: "The guided recommendation layer that ties cleanup, updates, storage, and system pressure together.",
                symbol: "sparkles.rectangle.stack.fill"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    statHeader("Score", "\(model.smartCareScore)", AppPalette.accent)

                    Text(model.recommendedActions.first?.detail ?? "No recommendations yet. Open Smart Care after the first few scans to get a fuller maintenance picture.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Open Smart Care") {
                        model.open(section: .smartCare)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            DashboardPanel(
                title: "Cleanup Outlook",
                subtitle: "What SK Mole can reclaim from safe cache, download, and leftover targets right now.",
                symbol: "trash.slash"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    statHeader("Reclaimable", ByteFormatting.format(model.cleanupBytes), AppPalette.amber)
                    Text("\(model.cleanupCategories.filter { !$0.candidates.isEmpty }.count) sections currently contain reviewable items.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let cleanupProgress = model.cleanupProgress {
                        InlineScanProgressView(progress: cleanupProgress, tint: AppPalette.accent)
                    }
                }
            }

            DashboardPanel(
                title: "Storage Footprint",
                subtitle: "Top tracked categories plus the current inspection mode for the startup and external volumes.",
                symbol: "chart.pie"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    statHeader("Tracked", ByteFormatting.format(model.storageReport?.totalTrackedBytes ?? 0), AppPalette.rose)
                    Text(model.storageReport == nil
                        ? "Run Storage to build the volume browser and space map."
                        : "\(model.storageReport?.sections.count ?? 0) tracked sections • \(model.storageInspectionMode.title)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let storageProgress = model.storageProgress {
                        InlineScanProgressView(progress: storageProgress, tint: AppPalette.sky)
                    }
                }
            }

            DashboardPanel(
                title: "Network Inspector",
                subtitle: "Processes, connections, and remote hosts stay lazy until you open them, which keeps the app lighter during everyday use.",
                symbol: "network"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    statHeader("Processes", "\(model.networkReport?.processes.count ?? 0)", AppPalette.sky)
                    Text(model.networkReport == nil
                        ? "No network snapshot yet."
                        : "\(model.networkReport?.activeConnectionCount ?? 0) active connections across \(model.networkReport?.remoteHosts.count ?? 0) remote hosts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Open Network Inspector") {
                        model.open(section: .network)
                    }
                    .buttonStyle(.bordered)
                }
            }

            DashboardPanel(
                title: "Process Inspector",
                subtitle: "Review active work by CPU or memory, then safely terminate only user-owned processes that SK Mole allows.",
                symbol: "list.bullet.rectangle.portrait"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    statHeader("Snapshot", "\(model.processInspectorItems.count)", AppPalette.accent)
                    Text(model.processInspectorItems.isEmpty
                        ? "No process snapshot yet."
                        : "\(model.processInspectorItems.filter(SystemGuard.canTerminateSnapshot).count) processes are safe to terminate from SK Mole.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Open Process Inspector") {
                        model.open(section: .processes)
                    }
                    .buttonStyle(.bordered)
                }
            }

            DashboardPanel(
                title: "Companion",
                subtitle: "The menu bar companion stays icon-only in the bar, but now opens a denser popover with update awareness and live status.",
                symbol: "menubar.rectangle"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    statHeader("State", model.menuBarCompanionState.isRunning ? "Running" : "Stopped", AppPalette.mint)
                    Text(model.menuBarCompanionState.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Open Settings") {
                        openSettings()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var updatePulsePanel: some View {
        DashboardPanel(
            title: "Update Pulse",
            subtitle: "Actionable updates stay separate from ignored and deferred versions, with release-note previews handled in the Updates tab.",
            symbol: "arrow.triangle.2.circlepath.circle"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                statHeader("Actionable", "\(model.activeAvailableUpdateItems.count)", AppPalette.sky)

                HStack(spacing: 10) {
                    monitoringFact(
                        title: "Automatic",
                        value: "\(model.activeAvailableUpdateItems.filter(\.canAutoInstall).count)",
                        detail: "installable from SK Mole",
                        tint: AppPalette.accent
                    )

                    monitoringFact(
                        title: "Muted",
                        value: "\(model.ignoredUpdateItems.count + model.deferredUpdateItems.count)",
                        detail: "ignored or deferred",
                        tint: AppPalette.amber
                    )
                }

                Text(updateScheduleSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Open Updates") {
                        model.open(section: .updates)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Scan Now") {
                        Task { await model.refreshUpdates() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var updateScheduleSummary: String {
        if let scannedAt = model.updateStatusSnapshot?.scannedAt {
            return "Last check \(scannedAt.formatted(date: .abbreviated, time: .shortened)) • schedule \(model.updateCheckInterval.title)"
        }

        return "No update scan has completed yet."
    }

    private var topProcessesSection: some View {
        DashboardPanel(
            title: "Top Processes",
            subtitle: "A throttled five-second snapshot of the apps and processes currently driving CPU and memory pressure.",
            symbol: "list.bullet.rectangle.portrait"
        ) {
            TopProcessList(processes: monitor.metrics.topProcesses)
                .allowsHitTesting(false)
        }
    }

    private func historyPanel(
        title: String,
        subtitle: String,
        value: String,
        tint: Color,
        points: [MetricHistoryPoint]
    ) -> some View {
        DashboardPanel(title: title, subtitle: subtitle, symbol: "chart.line.uptrend.xyaxis") {
            VStack(alignment: .leading, spacing: 10) {
                statHeader(title, value, tint)
                HistorySparkline(points: points, tint: tint)
            }
        }
    }

    private func heroStat(title: String, value: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.14))
        )
    }

    private func chip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .foregroundStyle(tint)
    }

    private func dashboardAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
    }

    private func statHeader(_ title: String, _ value: String, _ tint: Color) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
        }
    }

    private func monitoringFact(title: String, value: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.55))
        )
    }

    private var pressureTint: Color {
        switch monitor.metrics.memoryPressure {
        case .nominal:
            return AppPalette.accent
        case .elevated:
            return AppPalette.amber
        case .high:
            return AppPalette.rose
        }
    }

    private var pressureProgress: Double {
        switch monitor.metrics.memoryPressure {
        case .nominal:
            return 0.24
        case .elevated:
            return 0.62
        case .high:
            return 1
        }
    }

    private var thermalTint: Color {
        switch monitor.metrics.thermalState {
        case .nominal:
            return AppPalette.sky
        case .fair:
            return AppPalette.amber
        case .serious, .critical:
            return AppPalette.rose
        }
    }

    private var thermalProgress: Double {
        switch monitor.metrics.thermalState {
        case .nominal:
            return 0.18
        case .fair:
            return 0.55
        case .serious:
            return 0.82
        case .critical:
            return 1
        }
    }

    private var powerSymbol: String {
        guard let powerSource = monitor.metrics.powerSource else {
            return "powerplug"
        }

        if powerSource.isCharging {
            return "battery.100.bolt"
        }

        switch powerSource.source {
        case "Battery Power":
            return "battery.75"
        case "UPS Power":
            return "powerplug"
        default:
            return "powerplug"
        }
    }

    private func metricColumns(for width: CGFloat) -> [GridItem] {
        let count: Int

        switch width {
        case ..<860:
            count = 2
        case ..<1240:
            count = 3
        default:
            count = 4
        }

        return Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
    }

    private func boardColumns(for width: CGFloat) -> [GridItem] {
        let count: Int

        switch width {
        case ..<930:
            count = 1
        case ..<1480:
            count = 2
        default:
            count = 3
        }

        return Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
    }
}

private struct DashboardPanel<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let content: Content

    init(title: String, subtitle: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppPalette.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(AppPalette.accent.opacity(0.12)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06))
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 8)
    }
}
