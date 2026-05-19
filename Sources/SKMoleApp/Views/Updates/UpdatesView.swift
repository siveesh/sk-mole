import AppKit
import SwiftUI

struct UpdatesView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let updatesError = model.updatesError {
                    errorBanner(updatesError)
                }

                filterSection
                availableSection
                manualSection
                deferredSection
                ignoredSection
                unsupportedSection
                upToDateSection
                logsSection
            }
            .padding(28)
        }
    }

    private var header: some View {
        SectionCard(
            title: "Application updates",
            subtitle: "Check App Store apps, third-party downloads, Homebrew installs, and GitHub-sourced releases from one place. SK Mole installs what it can automate and links out when the source still controls the update flow.",
            symbol: "arrow.triangle.2.circlepath.circle"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(summaryTitle)
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text(summarySubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let scannedAt = model.updateReport?.scannedAt {
                            Text("Last checked \(scannedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 12) {
                        metricRow(title: "Available", value: "\(model.activeAvailableUpdateItems.count)")
                        metricRow(title: "Automatic", value: "\(model.activeAvailableUpdateItems.filter(\.canAutoInstall).count)")
                        metricRow(title: "Manual", value: "\(model.updateReport?.manualItems.count ?? 0)")
                        metricRow(title: "Deferred", value: "\(model.deferredUpdateItems.count)")
                        metricRow(title: "Ignored", value: "\(model.ignoredUpdateItems.count)")
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Button("Scan for Updates") {
                            Task { await model.refreshUpdates() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.updatesBusy)

                        Button("Install All Automatic") {
                            Task { await model.installAllAutomaticUpdates() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.updatesBusy || model.activeAvailableUpdateItems.filter(\.canAutoInstall).isEmpty)

                        if !model.ignoredUpdateItems.isEmpty || !model.deferredUpdateItems.isEmpty {
                            Button("Reset Ignore / Defer") {
                                model.resetUpdateDecisions()
                            }
                            .buttonStyle(.bordered)
                        }

                        if !(model.updateReport?.appStoreAutomation.isInstalled ?? false) {
                            Button("Install mas") {
                                Task { await model.installMASFromUpdates() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.updatesBusyActionID == "install-mas")
                        }

                        if model.updatesBusy {
                            ProgressView()
                        }
                    }

                    if let progress = model.updatesProgress {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(progress.detail)
                                .font(.subheadline.weight(.semibold))
                            ProgressView(
                                value: Double(progress.completedUnits),
                                total: Double(max(progress.totalUnits, 1))
                            )
                        }
                    }
                }

                selfUpdateCard
                appStoreAutomationCard
                updateScheduleCard
            }
        }
    }

    private var filterSection: some View {
        SectionCard(
            title: "Filters",
            subtitle: "Focus on updates that need action now, automatic installs that SK Mole can run directly, or manual checks that still depend on a vendor or release page.",
            symbol: "line.3.horizontal.decrease.circle"
        ) {
            HStack(spacing: 12) {
                TextField("Search applications, sources, or versions", text: $model.updatesSearchQuery)
                    .textFieldStyle(.roundedBorder)

                Picker("Filter", selection: $model.updatesFilter) {
                    ForEach(AppUpdateListFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
            }
        }
    }

    private var availableSection: some View {
        SectionCard(
            title: "Available Updates",
            subtitle: "These sources report a newer version than the one currently installed on this Mac, and they are still actionable because they have not been deferred or ignored.",
            symbol: "arrow.up.circle.fill"
        ) {
            let items = model.filteredAvailableUpdateItems

            if items.isEmpty {
                emptyState(
                    title: "No Available Updates",
                    systemImage: "checkmark.circle",
                    description: "SK Mole did not find any newer versions inside the currently visible filter."
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { item in
                        updateRow(item)
                    }
                }
            }
        }
    }

    private var manualSection: some View {
        SectionCard(
            title: "Manual Review",
            subtitle: "These entries have an update source or check result, but the final install still belongs to the vendor, App Store sign-in, or a release page.",
            symbol: "hand.raised"
        ) {
            let items = model.filteredManualUpdateItems

            if items.isEmpty {
                emptyState(
                    title: "No Manual Review Items",
                    systemImage: "checkmark.shield",
                    description: "The current filter does not contain any vendor-controlled or manual-review update paths."
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { item in
                        updateRow(item)
                    }
                }
            }
        }
    }

    private var deferredSection: some View {
        SectionCard(
            title: "Deferred Updates",
            subtitle: "These updates are still known, but SK Mole is holding them out of the active queue until the defer window expires.",
            symbol: "clock.badge.pause"
        ) {
            let items = model.filteredDeferredUpdateItems

            if items.isEmpty {
                emptyState(
                    title: "No Deferred Updates",
                    systemImage: "clock.badge.checkmark",
                    description: "Deferred items will appear here after you snooze an update for a day or a week."
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { item in
                        updateRow(item)
                    }
                }
            }
        }
    }

    private var ignoredSection: some View {
        SectionCard(
            title: "Ignored Versions",
            subtitle: "These versions are currently muted, which is helpful when you want to stay on a known-good build without losing the source record.",
            symbol: "bell.slash"
        ) {
            let items = model.filteredIgnoredUpdateItems

            if items.isEmpty {
                emptyState(
                    title: "No Ignored Versions",
                    systemImage: "bell",
                    description: "Ignored updates will appear here after you mute a specific release."
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { item in
                        updateRow(item)
                    }
                }
            }
        }
    }

    private var unsupportedSection: some View {
        SectionCard(
            title: "Untracked Apps",
            subtitle: "These installed apps did not advertise a structured update source inside the bundle, so SK Mole cannot verify a latest version yet.",
            symbol: "questionmark.app"
        ) {
            let items = model.filteredUnsupportedUpdateItems

            if items.isEmpty {
                emptyState(
                    title: "No Untracked Apps In View",
                    systemImage: "tray",
                    description: "Either every visible app has a structured source, or the current filter is hiding untracked entries."
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { item in
                        updateRow(item)
                    }
                }
            }
        }
    }

    private var upToDateSection: some View {
        SectionCard(
            title: "Up to Date",
            subtitle: "These sources were checked successfully and currently match the installed version.",
            symbol: "checkmark.circle.fill"
        ) {
            let items = model.filteredUpToDateUpdateItems

            if items.isEmpty {
                emptyState(
                    title: "No Up-To-Date Entries In View",
                    systemImage: "checkmark.circle",
                    description: "Switch the filter to `All` if you want to browse verified up-to-date applications and packages."
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { item in
                        updateRow(item)
                    }
                }
            }
        }
    }

    private var logsSection: some View {
        SectionCard(
            title: "Update Actions",
            subtitle: "Recent install attempts and automation output captured from Homebrew or `mas`.",
            symbol: "terminal"
        ) {
            if model.updateLogs.isEmpty {
                Text("Run an install or update action from this tab and SK Mole will keep the output here for quick troubleshooting.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.updateLogs.prefix(10)) { log in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(log.actionTitle, systemImage: log.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.headline)
                                    .foregroundStyle(log.succeeded ? AppPalette.mint : AppPalette.rose)

                                Spacer()

                                Text(log.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(log.output)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppPalette.secondaryCard.opacity(0.72))
                        )
                    }
                }
            }
        }
    }

    private var appStoreAutomationCard: some View {
        let automation = model.updateReport?.appStoreAutomation
            ?? AppStoreAutomationStatus(executablePath: nil, version: nil, accountName: nil, accountDetail: nil)

        return VStack(alignment: .leading, spacing: 12) {
            Label("Mac App Store automation", systemImage: "storefront")
                .font(.headline)

            Text(automation.summary)
                .font(.subheadline.weight(.semibold))

            Text(automation.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let executablePath = automation.executablePath {
                Text(executablePath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                UpdateCommandSnippetCard(title: "Install mas", command: AppStoreAutomationStatus.installCommand)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.72))
        )
    }

    private var selfUpdateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Label("SK Mole auto update", systemImage: "sparkles.rectangle.stack")
                    .font(.headline)

                Spacer()

                if model.updatesBusyActionID == AppUpdateService.selfUpdateItemID {
                    ProgressView()
                }
            }

            if let item = model.selfUpdateItem {
                Text(item.versionSummary)
                    .font(.subheadline.weight(.semibold))

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    if item.canAutoInstall {
                        Button("Download and Open DMG") {
                            Task { await model.installUpdate(item) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.updatesBusyActionID == item.id)
                    }

                    Button(item.releaseNotesURLTitle ?? "Open Release") {
                        model.openReleaseNotes(for: item)
                    }
                    .buttonStyle(.bordered)

                    if item.status == .upToDate {
                        Label("Current build is up to date", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppPalette.mint)
                    }
                }
            } else {
                Text("Run a scan and SK Mole will check its own GitHub Releases feed before checking other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Check SK Mole Release") {
                    Task { await model.refreshUpdates() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.72))
        )
    }

    private var updateScheduleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Scheduled checks", systemImage: "calendar.badge.clock")
                .font(.headline)

            Text(
                model.updateCheckInterval == .off
                    ? "Automatic update checks are off. Turn them on in Settings if you want SK Mole to keep a fresh update snapshot for the dashboard and menu bar companion."
                    : "SK Mole is set to check for updates \(model.updateCheckInterval.title.lowercased()). The menu bar companion can surface the last known results without making the Mac noisier."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let lastScheduledUpdateCheck = model.lastScheduledUpdateCheck {
                Text("Last scheduled check \(lastScheduledUpdateCheck.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.72))
        )
    }

    private var summaryTitle: String {
        guard model.updateReport != nil else {
            return "Ready to scan"
        }

        if model.activeAvailableUpdateItems.isEmpty {
            return "No updates found"
        }

        return "\(model.activeAvailableUpdateItems.count) actionable update\(model.activeAvailableUpdateItems.count == 1 ? "" : "s")"
    }

    private var summarySubtitle: String {
        guard let report = model.updateReport else {
            return "Scan applications and packages to compare installed versions against App Store metadata, Sparkle feeds, GitHub releases, and Homebrew inventory."
        }

        return "Checked \(report.scannedApplicationCount) apps and \(report.scannedPackageCount) Homebrew packages. \(model.activeAvailableUpdateItems.filter(\.canAutoInstall).count) update\(model.activeAvailableUpdateItems.filter(\.canAutoInstall).count == 1 ? "" : "s") can be installed directly from SK Mole, while \(model.ignoredUpdateItems.count + model.deferredUpdateItems.count) item\(model.ignoredUpdateItems.count + model.deferredUpdateItems.count == 1 ? "" : "s") are currently muted."
    }

    private func metricRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
        }
        .frame(minWidth: 90, alignment: .leading)
    }

    private func updateRow(_ item: AppUpdateItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if let appURL = item.appURL {
                AppIconThumbnail(url: appURL, size: 42, cornerRadius: 10)
            } else {
                Image(systemName: item.sourceKind.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppPalette.accent)
                    .frame(width: 42, height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppPalette.secondaryCard.opacity(0.9))
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Text(item.displayName)
                        .font(.headline)

                    statusBadge(for: item)

                    Spacer()
                }

                HStack(spacing: 10) {
                    Label(item.sourceKind.title, systemImage: item.sourceKind.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(item.versionSummary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    if let publishedAt = item.publishedAt {
                        Text(publishedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let decisionSummary = model.updateDecisionSummary(for: item) {
                    Label(decisionSummary, systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.amber)
                }

                if let commandPreview = item.commandPreview {
                    Text(commandPreview)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                if let releaseNotesPreview = item.releaseNotesPreview {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What changed")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(releaseNotesPreview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppPalette.secondaryCard.opacity(0.45))
                    )
                }
            }

            Spacer(minLength: 14)

            VStack(alignment: .trailing, spacing: 8) {
                if item.canAutoInstall {
                    Button("Install") {
                        Task { await model.installUpdate(item) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.updatesBusyActionID == "install-all-updates" || model.updatesBusyActionID == item.id)
                }

                HStack(spacing: 8) {
                    if let primaryURLTitle = item.primaryURLTitle, item.primaryURL != nil {
                        Button(primaryURLTitle) {
                            model.openPrimarySource(for: item)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let secondaryURLTitle = item.secondaryURLTitle, item.secondaryURL != nil {
                        Button(secondaryURLTitle) {
                            model.openSecondarySource(for: item)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                HStack(spacing: 8) {
                    if item.releaseNotesURL != nil {
                        Button(item.releaseNotesURLTitle ?? "Open Notes") {
                            model.openReleaseNotes(for: item)
                        }
                        .buttonStyle(.bordered)
                    }

                    if item.fullReleaseNotesURL != nil {
                        Button(item.fullReleaseNotesURLTitle ?? "Open History") {
                            model.openFullReleaseHistory(for: item)
                        }
                        .buttonStyle(.bordered)
                    }

                    if item.appURL != nil {
                        ActionIconButton(symbol: "eye", label: "Reveal in Finder") {
                            model.revealInstalledUpdateItem(item)
                        }
                    }
                }

                if item.status == .updateAvailable {
                    Menu {
                        if model.deferredUpdateItems.contains(item) {
                            Button("Resume Update Alerts") {
                                model.clearUpdateDeferral(item)
                            }
                        } else if model.ignoredUpdateItems.contains(item) {
                            Button("Stop Ignoring This Version") {
                                model.stopIgnoringUpdate(item)
                            }
                        } else {
                            Button("Defer 1 Day") {
                                model.deferUpdate(item, by: 24 * 60 * 60)
                            }
                            Button("Defer 1 Week") {
                                model.deferUpdate(item, by: 7 * 24 * 60 * 60)
                            }
                            Divider()
                            Button("Ignore This Version") {
                                model.ignoreUpdate(item)
                            }
                        }
                    } label: {
                        Label("Manage", systemImage: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                }

                if model.updatesBusyActionID == item.id {
                    ProgressView()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.72))
        )
    }

    private func statusBadge(for item: AppUpdateItem) -> some View {
        let tint: Color
        switch item.status {
        case .updateAvailable:
            tint = item.canAutoInstall ? AppPalette.accent : AppPalette.amber
        case .upToDate:
            tint = AppPalette.mint
        case .manualCheck:
            tint = AppPalette.amber
        case .unsupported, .error:
            tint = AppPalette.rose
        }

        return Text(item.status.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.16))
            )
            .foregroundStyle(tint)
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppPalette.rose.opacity(0.86))
            )
    }

    private func emptyState(title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .frame(minHeight: 160)
    }
}

private struct UpdateCommandSnippetCard: View {
    let title: String
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Copy") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(command, forType: .string)
                }
                .buttonStyle(.bordered)
            }

            Text(command)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.72))
        )
    }
}
