import AppKit
import SwiftUI

struct MenuBarPanelView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if model.showFullDiskAccessBanner {
                compactPermissionsBanner
            }

            metrics
            spotlight
            quickStats
            sections
            footer
        }
        .frame(width: 360)
        .padding(16)
        .task {
            await model.prepareMenuBar()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SK Mole")
                    .font(.title3.weight(.bold))
                Text("Live Mac status, quick scan context, and one-click navigation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Open") {
                open(.dashboard)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            compactMetric("CPU", "\(Int((model.metrics.cpuUsage * 100).rounded()))%", AppPalette.accent)
            compactMetric("Memory", "\(Int((model.metrics.memoryUsage * 100).rounded()))%", AppPalette.amber)
            compactMetric("Thermal", model.metrics.thermalState.title, AppPalette.rose)
        }
    }

    private var spotlight: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let powerSource = model.metrics.powerSource {
                HStack(spacing: 10) {
                    Image(systemName: powerSymbol(for: powerSource))
                        .foregroundStyle(AppPalette.sky)
                    Text(powerSource.summary)
                        .font(.subheadline)
                }
            }

            if let topProcess = model.metrics.topProcesses.first {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.horizontal.circle")
                        .foregroundStyle(AppPalette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Top process")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(topProcess.name) • \(String(format: "%.1f%% CPU", topProcess.cpuPercent))")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var quickStats: some View {
        HStack(spacing: 12) {
            quickStatCard(
                title: "Cleanup",
                value: ByteFormatting.format(model.cleanupBytes),
                subtitle: model.cleanupBusy ? "scanning..." : "reclaimable",
                symbol: "sparkles.rectangle.stack"
            )

            quickStatCard(
                title: "Apps",
                value: "\(model.uninstallableAppsCount)",
                subtitle: model.uninstallBusy ? "refreshing..." : "tracked",
                symbol: "xmark.app"
            )
        }
    }

    private var sections: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            sectionButton(.dashboard)
            sectionButton(.cleanup)
            sectionButton(.uninstall)
            sectionButton(.storage)
            sectionButton(.optimize)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cleanupProgress = model.cleanupProgress {
                InlineScanProgressView(progress: cleanupProgress, tint: AppPalette.accent)
            } else if let applicationDiscoveryProgress = model.applicationDiscoveryProgress {
                InlineScanProgressView(progress: applicationDiscoveryProgress, tint: AppPalette.sky)
            }

            HStack(spacing: 10) {
                Button("Refresh") {
                    Task { await model.refreshFromMenuBar() }
                }
                .buttonStyle(.bordered)

                Button("Settings") {
                    openSettings()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Quit Fully") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var compactPermissionsBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Label("Full Disk Access Recommended", systemImage: "lock.shield")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Dismiss") {
                    model.dismissFullDiskAccessBanner()
                }
                .buttonStyle(.borderless)
            }

            Text(model.fullDiskAccessStatus.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Open Privacy & Security") {
                model.openFullDiskAccessSettings()
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.7))
        )
    }

    private func compactMetric(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }

    private func quickStatCard(title: String, value: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(AppPalette.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.weight(.bold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private func sectionButton(_ section: SidebarSection) -> some View {
        Button {
            open(section)
        } label: {
            HStack {
                Image(systemName: section.symbol)
                Text(section.title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
    }

    private func powerSymbol(for snapshot: PowerSourceSnapshot) -> String {
        if snapshot.isCharging {
            return "battery.100.bolt"
        }

        switch snapshot.source {
        case "Battery Power":
            return "battery.75"
        case "UPS Power":
            return "powerplug"
        default:
            return "powerplug"
        }
    }

    private func open(_ section: SidebarSection) {
        model.open(section: section)
        openWindow(id: "main-window")
        NSApp.activate(ignoringOtherApps: true)
    }
}
