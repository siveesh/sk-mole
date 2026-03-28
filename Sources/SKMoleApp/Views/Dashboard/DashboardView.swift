import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    metricsGrid(for: proxy.size.width)
                    monitoringBoards(for: proxy.size.width)
                    statusSections(for: proxy.size.width)
                    topProcessesSection
                }
                .padding(24)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("One native cockpit for cleanup, uninstalling, disk insight, and live Mac health.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("SK Mole now launches lighter, keeps the menu bar companion separate, and layers history plus process insight on top of the safety-first maintenance tools.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 8) {
                    Pill(title: "Menu bar monitor stays active", tint: AppPalette.accent)
                    Pill(title: "Lazy scans with visible progress", tint: AppPalette.sky)
                    Pill(title: "Full Disk Access guidance built in", tint: AppPalette.amber)
                }
            }

            HStack(spacing: 12) {
                Button("Refresh Current Section") {
                    Task { await model.refreshCurrentSelection() }
                }
                .buttonStyle(.borderedProminent)

                Button("Open Smart Care") {
                    model.open(section: .smartCare)
                }
                .buttonStyle(.bordered)

                Button("Refresh Monitoring") {
                    model.refreshFullDiskAccessStatus()
                }
                .buttonStyle(.bordered)

                Button("Settings") {
                    openSettings()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(AppPalette.heroGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
        )
    }

    private func metricsGrid(for width: CGFloat) -> some View {
        LazyVGrid(columns: metricColumns(for: width), alignment: .leading, spacing: 18) {
            MetricCard(
                title: "CPU",
                value: "\(Int((model.metrics.cpuUsage * 100).rounded()))%",
                detail: "\(max(model.metrics.perCoreUsage.count, 1)) cores sampled once per second",
                symbol: "cpu",
                tint: AppPalette.accent,
                progress: model.metrics.cpuUsage
            )

            MetricCard(
                title: "GPU",
                value: model.metrics.gpuActivity.map { "\((Int(($0 * 100).rounded())))%" } ?? "Live",
                detail: [model.metrics.gpuName, model.metrics.gpuCores.map { "\($0) cores" }, model.metrics.metalSupport]
                    .compactMap { $0 }
                    .joined(separator: " • "),
                symbol: "memorychip",
                tint: AppPalette.sky,
                progress: model.metrics.gpuActivity
            )

            MetricCard(
                title: "Memory",
                value: ByteFormatting.format(model.metrics.memoryUsed),
                detail: "of \(ByteFormatting.format(model.metrics.memoryTotal)) actively in use",
                symbol: "gauge.open.with.lines.needle.33percent",
                tint: AppPalette.amber,
                progress: model.metrics.memoryUsage
            )

            MetricCard(
                title: "Memory Pressure",
                value: model.metrics.memoryPressure.title,
                detail: "\(ByteFormatting.format(model.metrics.memoryCompressed)) compressed • \(ByteFormatting.format(model.metrics.memoryCached)) cached",
                symbol: model.metrics.memoryPressure.symbol,
                tint: pressureTint,
                progress: pressureProgress
            )

            MetricCard(
                title: "Swap",
                value: ByteFormatting.format(model.metrics.swapUsed),
                detail: model.metrics.swapTotal > 0 ? "of \(ByteFormatting.format(model.metrics.swapTotal)) allocated" : "No swap allocation right now",
                symbol: "rectangle.compress.vertical",
                tint: AppPalette.rose,
                progress: model.metrics.swapTotal > 0 ? model.metrics.swapUsage : nil
            )

            MetricCard(
                title: "Power",
                value: model.metrics.powerSource?.sourceTitle ?? "Unavailable",
                detail: model.metrics.powerSource?.summary ?? "No public power source details available on this Mac",
                symbol: powerSymbol,
                tint: AppPalette.mint,
                progress: model.metrics.powerSource?.batteryLevel
            )

            MetricCard(
                title: "Network Down",
                value: ByteFormatting.formatRate(model.metrics.networkDownloadRate),
                detail: "Current inbound throughput",
                symbol: "arrow.down.circle",
                tint: AppPalette.sky,
                progress: nil
            )

            MetricCard(
                title: "Network Up",
                value: ByteFormatting.formatRate(model.metrics.networkUploadRate),
                detail: "Current outbound throughput",
                symbol: "arrow.up.circle",
                tint: AppPalette.accent,
                progress: nil
            )

            MetricCard(
                title: "Disk",
                value: ByteFormatting.format(model.metrics.diskUsed),
                detail: "of \(ByteFormatting.format(model.metrics.diskTotal)) occupied",
                symbol: "internaldrive",
                tint: AppPalette.rose,
                progress: model.metrics.diskUsage
            )
        }
    }

    private func monitoringBoards(for width: CGFloat) -> some View {
        VStack(spacing: 18) {
            LazyVGrid(columns: boardColumns(for: width), alignment: .leading, spacing: 18) {
                historyCard(
                    title: "CPU History",
                    subtitle: "Recent total CPU load across all cores.",
                    value: "\(Int((model.metrics.cpuUsage * 100).rounded()))%",
                    tint: AppPalette.accent,
                    points: model.cpuHistory
                )

                historyCard(
                    title: "Memory History",
                    subtitle: "Resident memory usage as a share of physical RAM.",
                    value: "\(Int((model.metrics.memoryUsage * 100).rounded()))%",
                    tint: AppPalette.amber,
                    points: model.memoryHistory
                )

                SectionCard(
                    title: "Network History",
                    subtitle: "Recent inbound and outbound throughput without waiting for a separate trace.",
                    symbol: "arrow.left.and.right.circle"
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            statHeader("Down", ByteFormatting.formatRate(model.metrics.networkDownloadRate), AppPalette.sky)
                            HistorySparkline(points: model.downloadHistory, tint: AppPalette.sky)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            statHeader("Up", ByteFormatting.formatRate(model.metrics.networkUploadRate), AppPalette.accent)
                            HistorySparkline(points: model.uploadHistory, tint: AppPalette.accent)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
            }

            LazyVGrid(columns: boardColumns(for: width), alignment: .leading, spacing: 18) {
                SectionCard(
                    title: "Per-Core CPU",
                    subtitle: "Spot uneven bursts and single-core bottlenecks instead of relying on one aggregate number.",
                    symbol: "square.split.2x2"
                ) {
                    PerCoreUsageGrid(usage: model.metrics.perCoreUsage)
                }
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)

                SectionCard(
                    title: "Pressure and Thermal",
                    subtitle: "Public macOS signals for memory pressure and thermal headroom, even on Apple Silicon where raw fan data is not public.",
                    symbol: "waveform.path.ecg"
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        monitoringFact(
                            title: "Memory pressure",
                            value: model.metrics.memoryPressure.title,
                            detail: "\(ByteFormatting.format(model.metrics.memoryWired)) wired • \(ByteFormatting.format(model.metrics.memoryCompressed)) compressed",
                            tint: pressureTint
                        )

                        monitoringFact(
                            title: "Thermal state",
                            value: model.metrics.thermalState.title,
                            detail: "Thermal pressure reported by macOS",
                            tint: thermalTint
                        )
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)

                SectionCard(
                    title: "Power Snapshot",
                    subtitle: "Battery or external power context with enough detail to understand why performance or thermal behavior changed.",
                    symbol: powerSymbol
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        monitoringFact(
                            title: "Source",
                            value: model.metrics.powerSource?.sourceTitle ?? "Unavailable",
                            detail: model.metrics.powerSource?.summary ?? "This Mac did not return public battery details.",
                            tint: AppPalette.mint
                        )

                        monitoringFact(
                            title: "Last sample",
                            value: DateFormatter.localizedString(from: model.metrics.timestamp, dateStyle: .none, timeStyle: .medium),
                            detail: "Sampler cadence is one second for totals and five seconds for process ranking.",
                            tint: AppPalette.sky
                        )
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
            }
        }
    }

    private func statusSections(for width: CGFloat) -> some View {
        LazyVGrid(columns: boardColumns(for: width), alignment: .leading, spacing: 18) {
            SectionCard(
                title: "Smart Care",
                subtitle: "Guided recommendations pulled from cleanup, storage, permissions, and current system pressure.",
                symbol: "sparkles.rectangle.stack.fill"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(model.smartCareScore)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("\(model.recommendedActions.count) recommendation\(model.recommendedActions.count == 1 ? "" : "s") ready to review")
                        .foregroundStyle(.secondary)

                    Button("Open Smart Care") {
                        model.open(section: .smartCare)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)

            SectionCard(
                title: "Cleanup outlook",
                subtitle: "What SK Mole can reclaim from user-safe caches and leftovers right now.",
                symbol: "trash.slash"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(ByteFormatting.format(model.cleanupBytes))
                        .font(.system(size: 26, weight: .bold, design: .rounded))

                    Text("\(model.cleanupCategories.filter { !$0.candidates.isEmpty }.count) sections currently contain reclaimable items.")
                        .foregroundStyle(.secondary)

                    if let cleanupProgress = model.cleanupProgress {
                        InlineScanProgressView(progress: cleanupProgress, tint: AppPalette.accent)
                    } else if model.cleanupBusy {
                        ProgressView()
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)

            SectionCard(
                title: "Uninstall surface",
                subtitle: "Apps discovered in supported locations and eligible for safe preview-based removal.",
                symbol: "xmark.app"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(model.uninstallableAppsCount)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("user-removable apps discovered across /Applications and ~/Applications")
                        .foregroundStyle(.secondary)

                    if let applicationDiscoveryProgress = model.applicationDiscoveryProgress {
                        InlineScanProgressView(progress: applicationDiscoveryProgress, tint: AppPalette.sky)
                    } else if model.uninstallBusy {
                        ProgressView()
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)

            SectionCard(
                title: "Storage footprint",
                subtitle: "Top tracked categories from your home folders, apps, caches, and Trash.",
                symbol: "chart.pie"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(ByteFormatting.format(model.storageReport?.totalTrackedBytes ?? 0))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("tracked across \(model.storageReport?.sections.count ?? 0) categories")
                        .foregroundStyle(.secondary)

                    if let storageProgress = model.storageProgress {
                        InlineScanProgressView(progress: storageProgress, tint: AppPalette.sky)
                    } else if model.storageBusy {
                        ProgressView()
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        }
    }

    private var topProcessesSection: some View {
        SectionCard(
            title: "Top Processes",
            subtitle: "A throttled five-second snapshot of who is driving CPU and memory pressure right now, stretched across the full dashboard width for easier comparison.",
            symbol: "list.bullet.rectangle.portrait"
        ) {
            TopProcessList(processes: model.metrics.topProcesses)
        }
    }

    private func historyCard(
        title: String,
        subtitle: String,
        value: String,
        tint: Color,
        points: [MetricHistoryPoint]
    ) -> some View {
        SectionCard(title: title, subtitle: subtitle, symbol: "chart.line.uptrend.xyaxis") {
            VStack(alignment: .leading, spacing: 10) {
                statHeader(title, value, tint)
                HistorySparkline(points: points, tint: tint)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.55))
        )
    }

    private var pressureTint: Color {
        switch model.metrics.memoryPressure {
        case .nominal:
            return AppPalette.accent
        case .elevated:
            return AppPalette.amber
        case .high:
            return AppPalette.rose
        }
    }

    private var pressureProgress: Double {
        switch model.metrics.memoryPressure {
        case .nominal:
            return 0.33
        case .elevated:
            return 0.66
        case .high:
            return 1.0
        }
    }

    private var thermalTint: Color {
        switch model.metrics.thermalState {
        case .nominal:
            return AppPalette.accent
        case .fair:
            return AppPalette.amber
        case .serious, .critical:
            return AppPalette.rose
        }
    }

    private var powerSymbol: String {
        guard let powerSource = model.metrics.powerSource else {
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
        case ..<1180:
            count = 3
        default:
            count = 4
        }

        return Array(repeating: GridItem(.flexible(), spacing: 18), count: count)
    }

    private func boardColumns(for width: CGFloat) -> [GridItem] {
        let count = width < 980 ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 18), count: count)
    }
}
