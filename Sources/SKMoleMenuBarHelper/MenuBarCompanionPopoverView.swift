import SwiftUI
import SKMoleShared

final class MenuBarCompanionContentModel: ObservableObject {
    @Published var snapshot: MenuBarSnapshot?
    @Published var activeAlerts: [MenuBarActiveAlert] = []
    @Published var updateSnapshot: AppUpdateStatusSnapshot?
}

struct MenuBarCompanionPopoverView: View {
    @ObservedObject var model: MenuBarCompanionContentModel
    let openMainApp: () -> Void
    let openUpdates: () -> Void
    let openNetwork: () -> Void
    let openProcesses: () -> Void
    let openSmartCare: () -> Void
    let openPrivacySecurity: () -> Void
    let quitMainApp: () -> Void
    let quitCompanion: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                if let snapshot = model.snapshot {
                    hero(snapshot)

                    if !model.activeAlerts.isEmpty {
                        alertsCard
                    }

                    metricGrid(snapshot)
                    updatesStrip
                    topProcessesCard(snapshot)
                    footerActions
                } else {
                    loadingCard
                }
            }
            .padding(12)
        }
        .frame(width: 336)
        .background(CompanionPalette.canvas)
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Sampling your Mac...")
                .font(.headline)
            Text("SK Mole Companion keeps the menu bar light and fills in richer details when opened.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(16)
        .background(panelFill(cornerRadius: 24))
    }

    private func hero(_ snapshot: MenuBarSnapshot) -> some View {
        let score = healthScore(for: snapshot)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: healthSymbol(for: score))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(healthTint(for: score))

                Text("\(score)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text(healthTitle(for: score))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Button {
                    openMainApp()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.headline)
                }
                .buttonStyle(.plain)
                .help("Open SK Mole")
            }

            configurationChips(snapshot.systemConfiguration)
        }
        .padding(14)
        .background(panelFill(cornerRadius: 26))
    }

    private func configurationChips(_ configuration: MenuBarSystemConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                chip(configuration.modelName)
                chip(configuration.chipName)
            }

            HStack(spacing: 6) {
                chip(MenuBarHelperFormatting.formatBytes(configuration.memoryBytes))
                chip(configuration.osVersion)
                chip(configuration.uptime)
            }
        }
    }

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(model.activeAlerts.count) alert\(model.activeAlerts.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(CompanionPalette.warning)

            ForEach(model.activeAlerts.prefix(2)) { alert in
                Text(alert.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(CompanionPalette.warning.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(CompanionPalette.warning.opacity(0.24))
                )
        )
    }

    private func metricGrid(_ snapshot: MenuBarSnapshot) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            metricCard(
                title: "CPU",
                value: percent(snapshot.cpuUsage),
                detail: snapshot.topProcessName ?? "idle",
                systemImage: "cpu",
                tint: CompanionPalette.accent,
                progress: snapshot.cpuUsage
            )

            metricCard(
                title: "MEM",
                value: percent(snapshot.memoryUsage),
                detail: "\(MenuBarHelperFormatting.formatBytes(snapshot.memoryUsed)) / \(MenuBarHelperFormatting.formatBytes(snapshot.memoryTotal))",
                systemImage: "memorychip",
                tint: CompanionPalette.sand,
                progress: snapshot.memoryUsage
            )

            metricCard(
                title: "NET",
                value: MenuBarHelperFormatting.formatRate(snapshot.downloadRate),
                detail: "down \(MenuBarHelperFormatting.formatRate(snapshot.downloadRate))  up \(MenuBarHelperFormatting.formatRate(snapshot.uploadRate))",
                systemImage: "network",
                tint: CompanionPalette.sky,
                progress: nil
            )

            metricCard(
                title: "DISK",
                value: "\(Int(((1 - snapshot.diskFreeRatio) * 100).rounded()))%",
                detail: "\(MenuBarHelperFormatting.formatBytes(snapshot.diskFreeBytes)) free",
                systemImage: "internaldrive",
                tint: CompanionPalette.sky,
                progress: 1 - snapshot.diskFreeRatio
            )

            metricCard(
                title: "POWER",
                value: snapshot.batteryLevel.map { "\(Int(($0 * 100).rounded()))%" } ?? "AC",
                detail: snapshot.powerSummary ?? "AC power",
                systemImage: "bolt.fill",
                tint: CompanionPalette.amber,
                progress: snapshot.batteryLevel
            )

            metricCard(
                title: "THERMAL",
                value: thermalTitle(snapshot.thermalStateLevel),
                detail: "Pressure \(pressureTitle(snapshot.memoryPressureLevel))",
                systemImage: "thermometer.medium",
                tint: thermalTint(snapshot.thermalStateLevel),
                progress: Double(snapshot.thermalStateLevel) / 3
            )
        }
    }

    private var updatesStrip: some View {
        Button(action: openUpdates) {
            HStack(spacing: 10) {
                Label("Updates", systemImage: "arrow.triangle.2.circlepath.circle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()

                if let updateSnapshot = model.updateSnapshot {
                    Text("\(updateSnapshot.actionableCount) action")
                        .font(.callout.weight(.bold))

                    Text("\(updateSnapshot.automaticCount) auto")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("Open")
                        .font(.callout.weight(.bold))
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(panelFill(cornerRadius: 18))
    }

    private func topProcessesCard(_ snapshot: MenuBarSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Top processes", systemImage: "chart.bar.xaxis")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Inspect") {
                    openProcesses()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
            }

            if snapshot.topProcesses.isEmpty {
                Text("Process sampler is warming up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 6) {
                    processHeader

                    ForEach(snapshot.topProcesses.prefix(5)) { process in
                        processRow(process)
                    }
                }
            }
        }
        .padding(12)
        .background(panelFill(cornerRadius: 20))
    }

    private var processHeader: some View {
        HStack {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("CPU")
                .frame(width: 54, alignment: .trailing)
            Text("Memory")
                .frame(width: 72, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
    }

    private func processRow(_ process: MenuBarTopProcessSummary) -> some View {
        HStack(spacing: 8) {
            Text(process.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.1f%%", process.cpuPercent))
                .font(.caption.monospacedDigit())
                .frame(width: 54, alignment: .trailing)

            Text(MenuBarHelperFormatting.formatBytes(process.memoryBytes))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
    }

    private var footerActions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                footerButton("Open", systemImage: "circle.grid.2x2", action: openMainApp)
                footerButton("Updates", systemImage: "arrow.triangle.2.circlepath.circle", action: openUpdates)
                footerButton("Smart", systemImage: "sparkles", action: openSmartCare)
            }

            HStack(spacing: 8) {
                footerButton("Network", systemImage: "network", action: openNetwork)
                footerButton("Privacy", systemImage: "lock.shield", action: openPrivacySecurity)
                footerButton("Quit", systemImage: "power", action: quitCompanion)
            }
        }
    }

    private func metricCard(
        title: String,
        value: String,
        detail: String,
        systemImage: String,
        tint: Color,
        progress: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.heavy))
                    .tracking(1.6)
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
            }

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)

            Text(detail)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let progress {
                progressBar(value: progress, tint: tint)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(panelFill(cornerRadius: 18))
    }

    private func footerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.bold))
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CompanionPalette.control)
        )
    }

    private func chip(_ title: String) -> some View {
        Text(title)
            .font(.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CompanionPalette.control)
            )
    }

    private func progressBar(value: Double, tint: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: proxy.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 5)
    }

    private func panelFill(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(CompanionPalette.card)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }

    private func healthScore(for snapshot: MenuBarSnapshot) -> Int {
        var penalty = 0
        penalty += Int(min(35, snapshot.cpuUsage * 28))
        penalty += Int(min(25, snapshot.memoryUsage * 20))
        penalty += snapshot.diskFreeRatio < 0.12 ? 18 : 0
        penalty += snapshot.memoryPressureLevel * 8
        penalty += snapshot.thermalStateLevel * 8
        return max(0, min(100, 100 - penalty))
    }

    private func healthTitle(for score: Int) -> String {
        switch score {
        case 88...100:
            return "Excellent"
        case 70..<88:
            return "Good"
        case 50..<70:
            return "Watch"
        default:
            return "Strained"
        }
    }

    private func healthSymbol(for score: Int) -> String {
        score >= 70 ? "sun.max.fill" : "exclamationmark.triangle.fill"
    }

    private func healthTint(for score: Int) -> Color {
        switch score {
        case 88...100:
            return CompanionPalette.accent
        case 70..<88:
            return CompanionPalette.sky
        case 50..<70:
            return CompanionPalette.amber
        default:
            return CompanionPalette.warning
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func pressureTitle(_ level: Int) -> String {
        SharedMemoryPressureLevel(rawValue: level)?.title ?? "Stable"
    }

    private func thermalTitle(_ level: Int) -> String {
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

    private func thermalTint(_ level: Int) -> Color {
        switch level {
        case 2, 3:
            return CompanionPalette.warning
        case 1:
            return CompanionPalette.amber
        default:
            return CompanionPalette.sand
        }
    }
}

private enum CompanionPalette {
    static let accent = Color(red: 0.19, green: 0.78, blue: 0.66)
    static let sky = Color(red: 0.38, green: 0.65, blue: 0.92)
    static let sand = Color(red: 0.86, green: 0.73, blue: 0.49)
    static let amber = Color(red: 0.94, green: 0.66, blue: 0.25)
    static let warning = Color(red: 0.91, green: 0.42, blue: 0.34)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .underPageBackgroundColor).opacity(0.92)
    static let control = Color.primary.opacity(0.07)
}
