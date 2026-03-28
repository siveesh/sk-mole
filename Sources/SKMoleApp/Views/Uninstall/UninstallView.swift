import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct UninstallView: View {
    @ObservedObject var model: AppModel
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 22) {
            appsPane
            detailPane
        }
        .padding(28)
    }

    private var appsPane: some View {
        SectionCard(
            title: "App inventory",
            subtitle: "Alphabetized installed apps, plus apps already in Trash for SmartDelete-style leftover review.",
            symbol: "square.grid.2x2"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    TextField("Search apps", text: $model.appSearch)
                        .textFieldStyle(.roundedBorder)

                    Button("Refresh") {
                        Task { await model.refreshApplications() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.uninstallBusy)
                }

                if let applicationDiscoveryProgress = model.applicationDiscoveryProgress {
                    InlineScanProgressView(progress: applicationDiscoveryProgress, tint: AppPalette.sky)
                }

                dropZone

                if let uninstallError = model.uninstallError {
                    Text(uninstallError)
                        .foregroundStyle(AppPalette.rose)
                        .font(.subheadline)
                }

                if model.filteredApplications.isEmpty && model.filteredTrashedApplications.isEmpty {
                    ContentUnavailableView(
                        "No Matching Apps",
                        systemImage: "xmark.app",
                        description: Text("Try a different search or refresh the app inventory.")
                    )
                    .frame(minHeight: 320)
                } else {
                    List(selection: selectionBinding) {
                        if !model.filteredApplications.isEmpty {
                            Section("Installed") {
                                ForEach(model.filteredApplications) { app in
                                    appRow(app)
                                }
                            }
                        }

                        if !model.filteredTrashedApplications.isEmpty {
                            Section("Apps Already in Trash") {
                                ForEach(model.filteredTrashedApplications) { app in
                                    appRow(app)
                                }
                            }
                        }
                    }
                    .frame(minHeight: 420)
                }
            }
        }
        .frame(minWidth: 390)
    }

    private var detailPane: some View {
        SectionCard(
            title: "Removal preview",
            subtitle: "Preview a full uninstall, a SmartDelete leftover pass, or a reset that only clears user-domain app data.",
            symbol: "magnifyingglass.circle"
        ) {
            Group {
                if let app = model.selectedApp {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top) {
                            HStack(alignment: .top, spacing: 14) {
                                AppIconThumbnail(url: app.url, size: 58, cornerRadius: 14)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(app.name)
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                    Text(app.bundleIdentifier ?? "No bundle identifier found")
                                        .foregroundStyle(.secondary)
                                    Text(app.url.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Pill(
                                title: app.location.title,
                                tint: app.isInTrash ? AppPalette.amber : AppPalette.accent
                            )

                            Button {
                                model.reveal(app.url)
                            } label: {
                                Label("Reveal App", systemImage: "eye")
                            }
                            .buttonStyle(.bordered)
                        }

                        if let preview = model.uninstallPreview {
                            if !app.isInTrash {
                                HStack(spacing: 10) {
                                    previewModeButton(
                                        title: "Uninstall Preview",
                                        symbol: "xmark.app",
                                        isSelected: preview.mode == .removeAppAndRemnants
                                    ) {
                                        Task { await model.previewDefaultRemovalForSelectedApp() }
                                    }
                                    .disabled(model.uninstallBusy)

                                    previewModeButton(
                                        title: "Reset Preview",
                                        symbol: "arrow.counterclockwise",
                                        isSelected: preview.mode == .resetApp
                                    ) {
                                        Task { await model.previewResetForSelectedApp() }
                                    }
                                    .disabled(model.uninstallBusy)
                                }
                            } else {
                                Text("This app is already in Trash, so SK Mole will only review and remove leftovers that still live outside Trash.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 20) {
                                metricBlock(ByteFormatting.format(preview.removableBytes), primaryMetricSubtitle(for: preview))
                                metricBlock("\(preview.remnants.count)", remnantsMetricSubtitle(for: preview))
                                metricBlock("\(preview.associatedItems.count)", "related items")
                                Spacer()
                            }

                            if !preview.associatedItems.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Related extensions and login items")
                                        .font(.headline)

                                    ForEach(preview.associatedItems) { item in
                                        HStack(alignment: .center, spacing: 14) {
                                            Image(systemName: item.symbol)
                                                .foregroundStyle(item.disposition == .removedWithAppBundle ? AppPalette.accent : AppPalette.amber)
                                                .frame(width: 28)

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.displayName)
                                                    .font(.headline)
                                                Text("\(ByteFormatting.format(item.sizeBytes)) • \(item.rationale)")
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            Pill(
                                                title: item.disposition.title,
                                                tint: item.disposition == .removedWithAppBundle ? AppPalette.accent : AppPalette.amber
                                            )

                                            ActionIconButton(symbol: "eye", label: "Reveal \(item.displayName)") {
                                                model.reveal(item.url)
                                            }
                                        }
                                        .padding(14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .fill(AppPalette.secondaryCard.opacity(0.7))
                                        )
                                    }
                                }
                            }

                            if preview.remnants.isEmpty {
                                Text("No user-domain remnants were found for this app.")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("User-domain remnants")
                                        .font(.headline)

                                    ForEach(preview.remnants) { remnant in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(remnant.displayName)
                                                    .font(.headline)
                                                Text("\(ByteFormatting.format(remnant.sizeBytes)) • \(remnant.rationale)")
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            ActionIconButton(symbol: "eye", label: "Reveal \(remnant.displayName)") {
                                                model.reveal(remnant.url)
                                            }
                                        }
                                        .padding(14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .fill(AppPalette.secondaryCard.opacity(0.7))
                                        )
                                    }
                                }
                            }

                            HStack {
                                Button {
                                    Task { await model.removeSelectedApp() }
                                } label: {
                                    Label(preview.mode.actionTitle, systemImage: primaryActionSymbol(for: preview.mode))
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!canApply(preview) || model.uninstallBusy)

                                if !app.isInTrash && preview.mode == .removeAppAndRemnants {
                                    Button {
                                        Task {
                                            await model.previewResetForSelectedApp()
                                        }
                                    } label: {
                                        Label("Preview Reset Instead", systemImage: "arrow.counterclockwise")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(model.uninstallBusy)
                                }

                                if model.uninstallBusy {
                                    ProgressView()
                                }
                            }
                        } else {
                            ProgressView("Resolving remnants...")
                        }
                    }
                } else {
                    Text("Select an app or drop an installed `.app` bundle to inspect its removable support files.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dropZone: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.and.arrow.down.on.square")
                    .foregroundStyle(isDropTargeted ? AppPalette.accent : .secondary)
                Text("Drop an installed `.app` here to preview uninstall")
                .font(.subheadline.weight(.semibold))
                Spacer()
            }

            Text("This mirrors the fast AppCleaner-style workflow, Finder can send `.app` bundles here through `Open With SK Mole`, and apps already in Trash show up separately for SmartDelete review.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? AppPalette.accent : Color.primary.opacity(0.12),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isDropTargeted ? AppPalette.accent.opacity(0.08) : AppPalette.secondaryCard.opacity(0.45))
                )
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: handleDrop(providers:))
    }

    private var selectionBinding: Binding<String?> {
        Binding<String?>(
            get: { model.selectedApp?.id },
            set: { newValue in
                let allApps = model.filteredApplications + model.filteredTrashedApplications
                guard let newValue, let app = allApps.first(where: { $0.id == newValue }) else {
                    model.selectedApp = nil
                    model.uninstallPreview = nil
                    return
                }

                Task { await model.selectApp(app) }
            }
        )
    }

    private func metricBlock(_ value: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        HStack(spacing: 12) {
            AppIconThumbnail(url: app.url, size: 42, cornerRadius: 11)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.headline)
                Text(ByteFormatting.format(app.sizeBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if app.isInTrash {
                Pill(title: "Trash", tint: AppPalette.amber)
            }

            if app.isRunning {
                Pill(title: "Running", tint: AppPalette.sky)
            }

            if app.isProtected {
                Pill(title: "Protected", tint: AppPalette.rose)
            }
        }
        .padding(.vertical, 4)
    }

    private func primaryMetricSubtitle(for preview: UninstallPreview) -> String {
        switch preview.mode {
        case .removeAppAndRemnants:
            "bundle + removable remnants"
        case .resetApp:
            "resettable app data"
        case .removeLeftoversOnly:
            "leftovers outside Trash"
        }
    }

    private func remnantsMetricSubtitle(for preview: UninstallPreview) -> String {
        switch preview.mode {
        case .removeLeftoversOnly:
            "leftover items"
        case .removeAppAndRemnants, .resetApp:
            "user-domain remnants"
        }
    }

    private func primaryActionSymbol(for mode: UninstallPreviewMode) -> String {
        switch mode {
        case .resetApp:
            "arrow.counterclockwise"
        case .removeAppAndRemnants, .removeLeftoversOnly:
            "trash"
        }
    }

    private func canApply(_ preview: UninstallPreview) -> Bool {
        guard !preview.app.isProtected else {
            return false
        }

        switch preview.mode {
        case .removeAppAndRemnants:
            return true
        case .resetApp, .removeLeftoversOnly:
            return !preview.remnants.isEmpty
        }
    }

    @ViewBuilder
    private func previewModeButton(
        title: String,
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if isSelected {
            Button(action: action) {
                Label(title, systemImage: symbol)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(action: action) {
                Label(title, systemImage: symbol)
            }
            .buttonStyle(.bordered)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let candidates = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !candidates.isEmpty else {
            return false
        }

        Task {
            for provider in candidates {
                if let url = await loadDroppedFileURL(from: provider) {
                    await model.previewDroppedApplication(at: url)
                    break
                }
            }
        }

        return true
    }

    private func loadDroppedFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }

                if let nsURL = item as? NSURL, let url = nsURL as URL? {
                    continuation.resume(returning: url)
                    return
                }

                if let string = item as? String, let url = URL(string: string) {
                    continuation.resume(returning: url)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }
}
