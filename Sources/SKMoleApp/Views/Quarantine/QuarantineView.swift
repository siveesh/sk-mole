import AppKit
import SwiftUI

struct QuarantineView: View {
    @ObservedObject var model: AppModel
    @State private var selectedAppIDs: Set<String> = []

    private var selectedApps: [QuarantinedApplication] {
        model.quarantinedApplications.filter { selectedAppIDs.contains($0.id) }
    }

    private var focusedApp: QuarantinedApplication? {
        if selectedApps.count == 1 {
            return selectedApps.first
        }

        return model.selectedQuarantinedApp
    }

    var body: some View {
        HStack(spacing: 22) {
            appsPane
            detailPane
        }
        .padding(28)
        .onChange(of: model.quarantinedApplications.map(\.id)) { _, ids in
            selectedAppIDs = selectedAppIDs.intersection(Set(ids))
        }
    }

    private var appsPane: some View {
        SectionCard(
            title: "Apple quarantine review",
            subtitle: "List app bundles that still carry `com.apple.quarantine`, show their signature state, and let you deliberately run `xattr` for selected apps.",
            symbol: "shield.slash"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    TextField("Search quarantined apps", text: $model.quarantineSearch)
                        .textFieldStyle(.roundedBorder)

                    Button("Refresh") {
                        Task { await model.refreshQuarantinedApplications() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.quarantineBusy)
                }

                HStack {
                    Text("\(selectedApps.count) selected")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Clear Selection") {
                        selectedAppIDs.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedApps.isEmpty)

                    Button {
                        Task {
                            await model.removeQuarantine(from: selectedApps)
                            selectedAppIDs.removeAll()
                        }
                    } label: {
                        Label("Run xattr", systemImage: "terminal")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedApps.isEmpty || model.quarantineBusyActionID != nil)
                }

                Text("SK Mole only removes the `com.apple.quarantine` attribute. It does not repair missing signatures, notarization, or other Gatekeeper trust issues.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let quarantineProgress = model.quarantineProgress {
                    InlineScanProgressView(progress: quarantineProgress, tint: AppPalette.amber)
                }

                if let quarantineError = model.quarantineError {
                    Text(quarantineError)
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.rose)
                }

                if model.filteredQuarantinedApplications.isEmpty {
                    ContentUnavailableView(
                        "No Quarantined Apps Found",
                        systemImage: "checkmark.shield",
                        description: Text("SK Mole did not find any app bundles in the reviewed locations that still carry `com.apple.quarantine`.")
                    )
                    .frame(minHeight: 360)
                } else {
                    List {
                        ForEach(model.filteredQuarantinedApplications) { app in
                            appRow(app)
                        }
                    }
                    .frame(minHeight: 420)
                }
            }
        }
        .frame(minWidth: 430)
    }

    private var detailPane: some View {
        SectionCard(
            title: "xattr detail",
            subtitle: "Review the signature state, raw quarantine attribute, and exact command before removing quarantine from an app.",
            symbol: "terminal"
        ) {
            ScrollView {
                Group {
                    if selectedApps.count > 1 {
                        bulkSelectionSummary
                    } else if let app = focusedApp {
                        singleAppDetail(app)
                    } else {
                        ContentUnavailableView(
                            "Select a Quarantined App",
                            systemImage: "shield.slash",
                            description: Text("Choose an app from the list to inspect its signature state and run `xattr -d com.apple.quarantine`.")
                        )
                        .frame(minHeight: 360)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func appRow(_ app: QuarantinedApplication) -> some View {
        let isSelected = selectedAppIDs.contains(app.id)

        return HStack(alignment: .center, spacing: 14) {
            SelectionCircleButton(
                isSelected: isSelected,
                accessibilityLabel: isSelected ? "Deselect \(app.name)" : "Select \(app.name)"
            ) {
                toggleSelection(for: app)
            }

            Button {
                model.selectQuarantinedApplication(app)
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    AppIconThumbnail(url: app.url, size: 42, cornerRadius: 11)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name)
                            .font(.headline)
                        Text(app.bundleIdentifier ?? "No bundle identifier found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(app.locationSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Pill(title: "Quarantined", tint: AppPalette.amber)
                    Pill(title: app.signatureStatus.title, tint: tint(for: app.signatureStatus))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(rowBackground(for: app, isSelected: isSelected))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func singleAppDetail(_ app: QuarantinedApplication) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                AppIconThumbnail(url: app.url, size: 60, cornerRadius: 15)

                VStack(alignment: .leading, spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(app.bundleIdentifier ?? "No bundle identifier found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(app.url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                ActionIconButton(symbol: "eye", label: "Reveal \(app.name)") {
                    model.reveal(app.url)
                }

                Button {
                    Task { await model.removeQuarantine(from: [app]) }
                } label: {
                    Label("Run xattr", systemImage: "terminal")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.quarantineBusyActionID == app.id)
            }

            HStack(spacing: 8) {
                Pill(title: "Quarantined", tint: AppPalette.amber)
                Pill(title: app.signatureStatus.title, tint: tint(for: app.signatureStatus))
            }

            HStack(spacing: 16) {
                metricBlock(title: "Size", value: ByteFormatting.format(app.sizeBytes))
                metricBlock(title: "Modified", value: modificationDateString(for: app))
            }

            Text(app.signatureStatus.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppPalette.secondaryCard.opacity(0.72))
                )

            QuarantineCommandCard(title: "xattr command", command: app.xattrCommand)
            QuarantineCommandCard(title: "Raw quarantine attribute", command: app.quarantineValue, copyLabel: "Copy Attribute")

            if !model.quarantineLogs.isEmpty {
                logSection
            }
        }
    }

    private var bulkSelectionSummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Multiple apps selected")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text("SK Mole will run `xattr -d com.apple.quarantine` on each selected app bundle one by one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                metricBlock(title: "Apps", value: "\(selectedApps.count)")
                metricBlock(title: "Total size", value: ByteFormatting.format(selectedApps.reduce(0) { $0 + $1.sizeBytes }))
            }

            Button {
                Task {
                    await model.removeQuarantine(from: selectedApps)
                    selectedAppIDs.removeAll()
                }
            } label: {
                Label("Run xattr On Selected Apps", systemImage: "terminal")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedApps.isEmpty || model.quarantineBusyActionID != nil)

            if !model.quarantineLogs.isEmpty {
                logSection
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent xattr actions")
                .font(.headline)

            ForEach(model.quarantineLogs.prefix(6)) { log in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(log.actionTitle)
                            .font(.headline)
                        Spacer()
                        Pill(title: log.succeeded ? "Succeeded" : "Failed", tint: log.succeeded ? AppPalette.accent : AppPalette.rose)
                    }

                    Text(log.output)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppPalette.secondaryCard.opacity(0.72))
                )
            }
        }
    }

    private func toggleSelection(for app: QuarantinedApplication) {
        if selectedAppIDs.contains(app.id) {
            selectedAppIDs.remove(app.id)
        } else {
            selectedAppIDs.insert(app.id)
        }
        model.selectQuarantinedApplication(app)
    }

    private func rowBackground(for app: QuarantinedApplication, isSelected: Bool) -> Color {
        if isSelected || focusedApp?.id == app.id {
            return AppPalette.accent.opacity(0.14)
        }

        return AppPalette.secondaryCard.opacity(0.72)
    }

    private func tint(for status: QuarantineSignatureStatus) -> Color {
        switch status {
        case .valid:
            AppPalette.accent
        case .unsigned:
            AppPalette.rose
        case .invalid:
            AppPalette.amber
        case .unknown:
            AppPalette.sky
        }
    }

    private func metricBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.72))
        )
    }

    private func modificationDateString(for app: QuarantinedApplication) -> String {
        guard let lastModified = app.lastModified else {
            return "Unknown"
        }

        return DateFormatter.localizedString(from: lastModified, dateStyle: .medium, timeStyle: .short)
    }
}

private struct QuarantineCommandCard: View {
    let title: String
    let command: String
    var copyLabel = "Copy"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(command)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            Button(copyLabel) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.72))
        )
    }
}
