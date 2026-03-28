import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                if model.showFullDiskAccessBanner {
                    permissionsBanner
                }

                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(AppPalette.canvas)
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            await model.prepareMainWindow()
        }
        .task(id: model.selection) {
            await model.prepareSelection()
        }
        .onOpenURL { url in
            Task { await model.handleIncomingURL(url) }
        }
    }

    private var sidebar: some View {
        List(
            SidebarSection.allCases,
            selection: Binding(
                get: { model.selection },
                set: { model.open(section: $0) }
            )
        ) { section in
            VStack(alignment: .leading, spacing: 6) {
                Label(section.title, systemImage: section.symbol)
                    .font(.headline)
                Text(section.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .tag(section)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "aqi.medium")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppPalette.accent)
                    Text("SK Mole")
                        .font(.title3.weight(.bold))
                }
                Text("Maintenance with guard rails, previews, and native performance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch model.selection {
        case .dashboard:
            DashboardView(model: model)
        case .smartCare:
            SmartCareView(model: model)
        case .cleanup:
            CleanupView(model: model)
        case .uninstall:
            UninstallView(model: model)
        case .storage:
            StorageView(model: model)
        case .optimize:
            OptimizeView(model: model)
        }
    }

    private var permissionsBanner: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppPalette.accent)

            VStack(alignment: .leading, spacing: 6) {
                Text("Full Disk Access Recommended")
                    .font(.headline)
                Text(model.fullDiskAccessStatus.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Open Settings") {
                model.openFullDiskAccessSettings()
            }
            .buttonStyle(.borderedProminent)

            Button("Dismiss") {
                model.dismissFullDiskAccessBanner()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.7))
        )
    }
}
