import AppKit
import SwiftUI

struct HomebrewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let homebrewError = model.homebrewError {
                    errorBanner(homebrewError)
                }

                maintenanceSection
                doctorSection

                HStack(alignment: .top, spacing: 22) {
                    installedPackagesPane
                    detailPane
                }

                discoverySection
                servicesSection
                developerSection
                logSection
            }
            .padding(28)
        }
    }

    private var header: some View {
        SectionCard(
            title: "Homebrew package manager",
            subtitle: "Install Homebrew if needed, then manage formulae, casks, services, updates, and cleanup through a native interface inspired by Cork.",
            symbol: "cup.and.saucer.fill"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.homebrewStatus.summary)
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text(model.homebrewStatus.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let executablePath = model.homebrewStatus.executablePath {
                            Text(executablePath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 12) {
                        if model.homebrewStatus.isInstalled {
                            metricRow(title: "Installed packages", value: "\(model.homebrewInventory?.installedPackages.count ?? 0)")
                            metricRow(title: "Outdated", value: "\(model.homebrewInventory?.outdatedCount ?? 0)")
                            metricRow(title: "Services", value: "\(model.homebrewServices.count)")
                        } else {
                            metricRow(title: "Installer", value: "Official Homebrew flow")
                            metricRow(title: "Command", value: "Terminal-driven")
                            metricRow(title: "Discovery", value: "Featured packages available")
                        }
                    }
                }

                HStack(spacing: 12) {
                    if model.homebrewStatus.isInstalled {
                        Button("Refresh Inventory") {
                            Task { await model.refreshHomebrew() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.homebrewBusy)
                    } else {
                        Button("Install Homebrew") {
                            model.launchHomebrewInstallerInTerminal()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Open Install Guide") {
                            model.openHomebrewInstallGuide()
                        }
                        .buttonStyle(.bordered)

                        Button("Copy Install Command") {
                            copyToPasteboard(HomebrewStatus.installCommand)
                        }
                        .buttonStyle(.bordered)
                    }

                    if model.homebrewBusy {
                        ProgressView()
                    }
                }

                if !model.homebrewStatus.isInstalled {
                    CommandSnippetCard(
                        title: "Official install command",
                        command: HomebrewStatus.installCommand
                    )
                }
            }
        }
    }

    private var maintenanceSection: some View {
        SectionCard(
            title: "Maintenance",
            subtitle: "Run the common Homebrew upkeep commands Cork users expect, with the exact brew command shown in the UI.",
            symbol: "wrench.and.screwdriver"
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                ForEach(HomebrewMaintenanceAction.allCases) { action in
                    VStack(alignment: .leading, spacing: 12) {
                        Label(action.title, systemImage: action.icon)
                            .font(.headline)

                        Text(action.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(action.command)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                        Text(action.caution)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button("Run") {
                                Task { await model.runHomebrewMaintenance(action) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.homebrewStatus.isInstalled || model.homebrewBusyActionID == "maintenance:\(action.id)")

                            Button("Copy") {
                                copyToPasteboard(action.command)
                            }
                            .buttonStyle(.bordered)
                        }

                        if model.homebrewBusyActionID == "maintenance:\(action.id)" {
                            ProgressView()
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppPalette.secondaryCard.opacity(0.72))
                    )
                }
            }
        }
    }

    private var doctorSection: some View {
        SectionCard(
            title: "Doctor Follow-Up",
            subtitle: "Surface actionable `brew doctor` findings directly in the UI, including unexpected dylibs that Homebrew recommends removing.",
            symbol: "stethoscope"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if model.homebrewDoctorLastOutput == nil {
                    Text("Run Homebrew Doctor from the maintenance section above and SK Mole will surface any unexpected dylibs or other actionable follow-up here.")
                        .foregroundStyle(.secondary)
                } else if model.homebrewDoctorIssues.isEmpty {
                    Text("The latest doctor run did not expose any unexpected dylibs with a safe in-app delete action.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.homebrewDoctorIssues) { issue in
                        doctorIssueCard(issue)
                    }
                }

                if let lastOutput = model.homebrewDoctorLastOutput, !lastOutput.isEmpty {
                    CommandSnippetCard(title: "Latest doctor output", command: lastOutput, copyLabel: "Copy Output")
                }
            }
        }
    }

    private var installedPackagesPane: some View {
        SectionCard(
            title: "Installed packages",
            subtitle: "Browse installed formulae and casks, filter by type or outdated status, and jump straight into package actions.",
            symbol: "shippingbox.circle"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    TextField("Filter installed packages", text: $model.homebrewInstalledFilter)
                        .textFieldStyle(.roundedBorder)

                    Picker("Filter", selection: $model.homebrewPackageFilter) {
                        ForEach(HomebrewPackageListFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if !model.homebrewStatus.isInstalled {
                    ContentUnavailableView(
                        "Install Homebrew First",
                        systemImage: "cup.and.saucer",
                        description: Text("Once Homebrew is installed, SK Mole will list your installed formulae and casks here.")
                    )
                    .frame(minHeight: 320)
                } else if model.filteredHomebrewPackages.isEmpty {
                    ContentUnavailableView(
                        "No Matching Packages",
                        systemImage: "shippingbox",
                        description: Text("Try a different filter, or install your first package from the discovery section below.")
                    )
                    .frame(minHeight: 320)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.filteredHomebrewPackages) { package in
                            installedPackageRow(package)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 420, maxWidth: 520, alignment: .topLeading)
    }

    private var detailPane: some View {
        SectionCard(
            title: "Package detail",
            subtitle: "Review package metadata, exact brew commands, and run install, upgrade, uninstall, cleanup, or service actions.",
            symbol: "info.circle"
        ) {
            if let detail = model.selectedHomebrewDetail {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: detail.kind.symbol)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(AppPalette.accent)
                            .frame(width: 46, height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppPalette.secondaryCard.opacity(0.72))
                            )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(detail.displayName)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            Text(detail.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(detail.token)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    packageBadgeRow(detail)

                    HStack(spacing: 18) {
                        detailMetric(title: "Installed", value: detail.installedVersion ?? "No")
                        detailMetric(title: "Latest", value: detail.latestVersion ?? "Unknown")
                        detailMetric(title: "Dependencies", value: "\(detail.dependencies.count)")
                        detailMetric(title: "Conflicts", value: "\(detail.conflicts.count)")
                    }

                    if let homepage = detail.homepage {
                        HStack(spacing: 12) {
                            Button("Open Homepage") {
                                NSWorkspace.shared.open(homepage)
                            }
                            .buttonStyle(.bordered)

                            Button("Copy Homepage") {
                                copyToPasteboard(homepage.absoluteString)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    actionButtons(detail)

                    if detail.hasService, detail.kind == .formula {
                        serviceActionButtons(detail)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        CommandSnippetCard(title: "Install", command: detail.installCommand)
                        CommandSnippetCard(title: "Upgrade", command: detail.upgradeCommand)
                        CommandSnippetCard(title: "Reinstall", command: detail.reinstallCommand)
                        CommandSnippetCard(title: "Uninstall", command: detail.uninstallCommand)
                        CommandSnippetCard(title: "Cleanup", command: detail.cleanupCommand)

                        if detail.hasService, detail.kind == .formula {
                            CommandSnippetCard(title: "Start Service", command: detail.serviceStartCommand)
                            CommandSnippetCard(title: "Stop Service", command: detail.serviceStopCommand)
                            CommandSnippetCard(title: "Restart Service", command: detail.serviceRestartCommand)
                        }
                    }

                    if !detail.dependencies.isEmpty {
                        infoTagSection(title: "Dependencies", values: detail.dependencies)
                    }

                    if !detail.conflicts.isEmpty {
                        infoTagSection(title: "Conflicts", values: detail.conflicts)
                    }

                    if let caveats = detail.caveats, !caveats.isEmpty {
                        Text(caveats)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(AppPalette.secondaryCard.opacity(0.72))
                            )
                    }

                    if model.homebrewDetailBusy {
                        ProgressView("Loading package detail…")
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select a Package",
                    systemImage: "cup.and.saucer",
                    description: Text("Choose an installed package or a discovery result to see commands, metadata, and management actions.")
                )
                .frame(minHeight: 320)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var discoverySection: some View {
        let isShowingRecommendations = model.homebrewSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let visibleResults = isShowingRecommendations ? model.recommendedHomebrewPackages : model.homebrewSearchResults

        return SectionCard(
            title: "Discover packages",
            subtitle: isShowingRecommendations
                ? "A broader starter catalog of recommended formulae and casks, with installed Homebrew packages and already-installed recommended apps hidden automatically."
                : "Search Homebrew formulae and casks by name or description. Installed items remain searchable, but the default recommendations stay focused on what is not already present.",
            symbol: "magnifyingglass"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    TextField("Search formulae and casks", text: $model.homebrewSearchQuery)
                        .textFieldStyle(.roundedBorder)

                    Button("Search") {
                        Task { await model.searchHomebrewPackages() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.homebrewSearchBusy)
                }

                if model.homebrewSearchBusy {
                    ProgressView()
                }

                if visibleResults.isEmpty {
                    Text(isShowingRecommendations ? "Every recommended item in the starter catalog already appears to be installed on this Mac." : "No packages matched this search.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
                        ForEach(visibleResults) { result in
                            discoverCard(result)
                        }
                    }
                }
            }
        }
    }

    private var servicesSection: some View {
        SectionCard(
            title: "brew services",
            subtitle: "Manage Homebrew-backed background services without dropping into the terminal.",
            symbol: "switch.2"
        ) {
            if model.homebrewServices.isEmpty {
                Text("No Homebrew services are currently registered on this Mac.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.homebrewServices) { service in
                        HStack(alignment: .center, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(service.name)
                                    .font(.headline)
                                Text(service.status)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let user = service.user, !user.isEmpty {
                                    Text("User: \(user)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button("Start") {
                                Task { await model.runHomebrewServiceAction("start", packageToken: service.name) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.homebrewBusyActionID == "service:start:\(service.name)")

                            Button("Stop") {
                                Task { await model.runHomebrewServiceAction("stop", packageToken: service.name) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.homebrewBusyActionID == "service:stop:\(service.name)")

                            Button("Restart") {
                                Task { await model.runHomebrewServiceAction("restart", packageToken: service.name) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.homebrewBusyActionID == "service:restart:\(service.name)")
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(AppPalette.secondaryCard.opacity(0.72))
                        )
                    }
                }
            }
        }
    }

    private var developerSection: some View {
        SectionCard(
            title: "GitHub CLI For Developers",
            subtitle: "Install `gh`, authenticate through your browser, verify the signed-in account, open token pages, and browse repositories owned by that account.",
            symbol: "chevron.left.forwardslash.chevron.right"
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.gitHubCLIStatus.summary)
                            .font(.system(size: 26, weight: .bold, design: .rounded))

                        Text(model.gitHubCLIStatus.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let executablePath = model.gitHubCLIStatus.executablePath {
                            Text(executablePath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 12) {
                        metricRow(title: "CLI", value: model.gitHubCLIStatus.version ?? "Not installed")
                        metricRow(title: "Signed In", value: model.gitHubCLIStatus.userLogin ?? "No")
                        metricRow(title: "Projects", value: "\(model.gitHubRepositories.count)")
                    }
                }

                if let gitHubCLIError = model.gitHubCLIError {
                    errorBanner(gitHubCLIError)
                }

                HStack(spacing: 12) {
                    if model.gitHubCLIStatus.isInstalled {
                        Button("Authenticate in Terminal") {
                            model.launchGitHubCLILoginInTerminal()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Refresh Status") {
                            Task { await model.refreshGitHubCLI() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.gitHubCLIBusy)

                        Button("Create Personal Access Token") {
                            model.openGitHubPersonalAccessTokenPage()
                        }
                        .buttonStyle(.bordered)

                        Button("Token Docs") {
                            model.openGitHubPersonalAccessTokenDocs()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Install GitHub CLI") {
                            Task { await model.installGitHubCLI() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.homebrewStatus.isInstalled || model.homebrewBusyActionID == "install:gh-cli")

                        Button("Open GitHub CLI") {
                            model.openGitHubCLIHomepage()
                        }
                        .buttonStyle(.bordered)

                        Button("Authentication Guide") {
                            model.openGitHubCLILoginGuide()
                        }
                        .buttonStyle(.bordered)
                    }

                    if model.gitHubCLIBusy || model.homebrewBusyActionID == "install:gh-cli" {
                        ProgressView()
                    }
                }

                if !model.homebrewStatus.isInstalled && !model.gitHubCLIStatus.isInstalled {
                    Text("Install Homebrew first if you want SK Mole to install GitHub CLI for you.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                CommandSnippetCard(title: "Install GitHub CLI", command: GitHubCLIStatus.installCommand)
                CommandSnippetCard(title: "Authenticate", command: GitHubCLIStatus.authCommand)

                if let authStatusOutput = model.gitHubCLIStatus.authStatusOutput, !authStatusOutput.isEmpty {
                    CommandSnippetCard(title: "Authentication status", command: authStatusOutput, copyLabel: "Copy Status")
                }

                if model.gitHubCLIStatus.isAuthenticated {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Repositories owned by the signed-in account")
                            .font(.headline)

                        if model.gitHubRepositories.isEmpty {
                            Text("No repositories were returned for this account yet. Refresh the status after authentication completes in Terminal.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.gitHubRepositories) { repository in
                                repositoryRow(repository)
                            }
                        }
                    }
                }
            }
        }
    }

    private var logSection: some View {
        SectionCard(
            title: "Homebrew command log",
            subtitle: "Output from package installs, updates, service commands, and maintenance tasks run from SK Mole.",
            symbol: "terminal"
        ) {
            if model.homebrewLogs.isEmpty {
                Text("No Homebrew actions have been run yet.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.homebrewLogs) { log in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(log.actionTitle)
                                    .font(.headline)
                                Spacer()
                                Pill(
                                    title: log.succeeded ? "Succeeded" : "Failed",
                                    tint: log.succeeded ? AppPalette.accent : AppPalette.rose
                                )
                            }

                            Text(log.output.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.system(.body, design: .monospaced))
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
        }
    }

    private func installedPackageRow(_ package: HomebrewInstalledPackage) -> some View {
        Button {
            Task { await model.selectHomebrewInstalledPackage(package) }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: package.kind.symbol)
                    .foregroundStyle(AppPalette.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(package.displayName)
                        .font(.headline)
                    Text(package.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(package.installedVersion ?? package.latestVersion ?? "Unknown version")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if package.isOutdated {
                    Pill(title: "Outdated", tint: AppPalette.amber)
                }

                if package.isPinned {
                    Pill(title: "Pinned", tint: AppPalette.sky)
                }

                if package.hasService {
                    Pill(title: "Service", tint: AppPalette.accent)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(rowBackground(for: package.reference))
            )
        }
        .buttonStyle(.plain)
    }

    private func discoverCard(_ result: HomebrewPackageSearchResult) -> some View {
        Button {
            Task { await model.selectHomebrewSearchResult(result) }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Label(result.displayName, systemImage: result.kind.symbol)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Pill(title: result.kind.title, tint: result.kind == .formula ? AppPalette.accent : AppPalette.sky)
                }

                Text(result.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(result.installCommand)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Text(result.source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(rowBackground(for: result.reference))
            )
        }
        .buttonStyle(.plain)
    }

    private func packageBadgeRow(_ detail: HomebrewPackageDetail) -> some View {
        HStack(spacing: 8) {
            Pill(title: detail.kind.title, tint: detail.kind == .formula ? AppPalette.accent : AppPalette.sky)

            if detail.isInstalled {
                Pill(title: "Installed", tint: AppPalette.accent)
            }

            if detail.isOutdated {
                Pill(title: "Outdated", tint: AppPalette.amber)
            }

            if detail.isPinned {
                Pill(title: "Pinned", tint: AppPalette.sky)
            }

            if detail.autoUpdates {
                Pill(title: "Auto updates", tint: AppPalette.sky)
            }

            if detail.hasService {
                Pill(title: "Service", tint: AppPalette.accent)
            }
        }
    }

    private func actionButtons(_ detail: HomebrewPackageDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if detail.isInstalled {
                    Button("Upgrade") {
                        Task { await model.upgradeSelectedHomebrewPackage() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.homebrewBusyActionID == "upgrade:\(detail.id)")

                    Button("Reinstall") {
                        Task { await model.reinstallSelectedHomebrewPackage() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.homebrewBusyActionID == "reinstall:\(detail.id)")

                    Button("Uninstall") {
                        Task { await model.uninstallSelectedHomebrewPackage() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.homebrewBusyActionID == "uninstall:\(detail.id)")

                    Button("Cleanup") {
                        Task { await model.cleanupSelectedHomebrewPackage() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.homebrewBusyActionID == "cleanup:\(detail.id)")
                } else {
                    Button("Install") {
                        Task { await model.installSelectedHomebrewPackage() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.homebrewStatus.isInstalled || model.homebrewBusyActionID == "install:\(detail.id)")
                }
            }

            if let actionID = model.homebrewBusyActionID, actionID.contains(detail.id) {
                ProgressView()
            }
        }
    }

    private func serviceActionButtons(_ detail: HomebrewPackageDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Service controls")
                .font(.headline)

            HStack(spacing: 12) {
                Button("Start") {
                    Task { await model.runHomebrewServiceAction("start", packageToken: detail.token) }
                }
                .buttonStyle(.bordered)
                .disabled(model.homebrewBusyActionID == "service:start:\(detail.token)")

                Button("Stop") {
                    Task { await model.runHomebrewServiceAction("stop", packageToken: detail.token) }
                }
                .buttonStyle(.bordered)
                .disabled(model.homebrewBusyActionID == "service:stop:\(detail.token)")

                Button("Restart") {
                    Task { await model.runHomebrewServiceAction("restart", packageToken: detail.token) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.homebrewBusyActionID == "service:restart:\(detail.token)")
            }
        }
    }

    private func doctorIssueCard(_ issue: HomebrewDoctorIssue) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(issue.title)
                .font(.headline)

            Text(issue.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !issue.paths.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(issue.paths) { path in
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(path.fileName)
                                    .font(.headline)
                                Text(path.path)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                if let note = path.note {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button("Reveal") {
                                model.reveal(URL(fileURLWithPath: path.path))
                            }
                            .buttonStyle(.bordered)

                            Button("Delete") {
                                Task { await model.deleteHomebrewDoctorPath(path) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!path.canDelete || model.homebrewBusyActionID == "doctor-delete:\(path.id)")
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppPalette.secondaryCard.opacity(0.72))
                        )
                    }
                }
            }

            if !issue.supportingLines.isEmpty {
                Text(issue.supportingLines.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.72))
        )
    }

    private func repositoryRow(_ repository: GitHubRepositorySummary) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(repository.nameWithOwner)
                    .font(.headline)

                if let description = repository.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(repository.updatedSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Pill(title: repository.visibility.capitalized, tint: repository.isPrivate ? AppPalette.rose : AppPalette.accent)

            if repository.isFork {
                Pill(title: "Fork", tint: AppPalette.sky)
            }

            if repository.isArchived {
                Pill(title: "Archived", tint: AppPalette.amber)
            }

            Button("Open") {
                model.openGitHubRepository(repository)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.72))
        )
    }

    private func infoTagSection(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            FlowTagList(values: values)
        }
    }

    private func detailMetric(title: String, value: String) -> some View {
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

    private func metricRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
        }
        .frame(width: 190, alignment: .leading)
    }

    private func rowBackground(for reference: HomebrewPackageReference) -> Color {
        if model.selectedHomebrewDetail?.reference == reference || model.homebrewSelectedFallbackResult?.reference == reference {
            return AppPalette.accent.opacity(0.16)
        }

        return AppPalette.secondaryCard.opacity(0.72)
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppPalette.rose)
            )
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct CommandSnippetCard: View {
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

private struct FlowTagList: View {
    let values: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppPalette.secondaryCard.opacity(0.72))
                    )
            }
        }
    }
}
