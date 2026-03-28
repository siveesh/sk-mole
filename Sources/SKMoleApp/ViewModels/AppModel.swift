import AppKit
import Foundation
import SKMoleShared
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    private enum PreferenceKey {
        static let startupPreference = "skmole.startupPreference"
        static let lastSelectedSection = "skmole.lastSelectedSection"
        static let autoRefreshOnOpen = "skmole.autoRefreshOnOpen"
        static let menuBarCompanionEnabled = "skmole.menuBarCompanionEnabled"
        static let showFullDiskAccessReminders = "skmole.showFullDiskAccessReminders"
        static let storageInspectionMode = "skmole.storageInspectionMode"
    }

    private enum HistoryLimit {
        static let points = 60
    }

    @Published var selection: SidebarSection = .dashboard {
        didSet {
            UserDefaults.standard.set(selection.rawValue, forKey: PreferenceKey.lastSelectedSection)
        }
    }

    @Published var startupPreference: StartupPreference = .rememberLast {
        didSet {
            UserDefaults.standard.set(startupPreference.rawValue, forKey: PreferenceKey.startupPreference)
        }
    }

    @Published var autoRefreshOnOpen = false {
        didSet {
            UserDefaults.standard.set(autoRefreshOnOpen, forKey: PreferenceKey.autoRefreshOnOpen)
        }
    }

    @Published var showFullDiskAccessReminders = true {
        didSet {
            UserDefaults.standard.set(showFullDiskAccessReminders, forKey: PreferenceKey.showFullDiskAccessReminders)
            updateFullDiskAccessBannerVisibility()
        }
    }

    @Published var menuBarCompanionEnabled = true {
        didSet {
            UserDefaults.standard.set(menuBarCompanionEnabled, forKey: PreferenceKey.menuBarCompanionEnabled)
            syncMenuBarCompanion(launchIfEnabled: menuBarCompanionEnabled)
        }
    }

    @Published var metrics: SystemMetricSnapshot = .placeholder
    @Published var cpuHistory: [MetricHistoryPoint] = []
    @Published var memoryHistory: [MetricHistoryPoint] = []
    @Published var downloadHistory: [MetricHistoryPoint] = []
    @Published var uploadHistory: [MetricHistoryPoint] = []
    @Published var recommendedActions: [RecommendedAction] = []
    @Published var showFullDiskAccessBanner = true
    @Published var fullDiskAccessStatus: FullDiskAccessStatus = .unknown {
        didSet {
            updateFullDiskAccessBannerVisibility()
        }
    }

    @Published var cleanupCategories: [CleanupCategorySummary] = []
    @Published var cleanupBusy = false
    @Published var cleanupError: String?
    @Published var cleanupProgress: ScanProgress?

    @Published var applications: [InstalledApp] = []
    @Published var trashedApplications: [InstalledApp] = []
    @Published var appSearch = ""
    @Published var selectedApp: InstalledApp?
    @Published var uninstallPreview: UninstallPreview?
    @Published var uninstallBusy = false
    @Published var uninstallError: String?
    @Published var applicationDiscoveryProgress: ScanProgress?

    @Published var storageReport: StorageReport?
    @Published var storageBusy = false
    @Published var storageError: String?
    @Published var storageProgress: ScanProgress?
    @Published var storageInspectionMode: StorageInspectionMode = .visible {
        didSet {
            UserDefaults.standard.set(storageInspectionMode.rawValue, forKey: PreferenceKey.storageInspectionMode)
        }
    }
    @Published var selectedStorageVolumeID: String?
    @Published var storageVolumeCurrentNode: StorageNode?
    @Published var storageVolumeBreadcrumb: [StorageNode] = []
    @Published var storageVolumeBusy = false
    @Published var storageVolumeError: String?

    @Published var optimizationLogs: [OptimizationLog] = []
    @Published var optimizationBusyActionID: String?
    @Published var privilegedHelperState: PrivilegedHelperState = .unavailable
    @Published var privilegedHelperError: String?
    @Published var privilegedHelperBusy = false
    @Published var privilegedHelperBusyTaskID: String?
    @Published var privilegedHelperReachability = "Not checked"
    @Published var menuBarCompanionState: MenuBarCompanionState = .unavailable
    @Published var menuBarCompanionError: String?
    @Published var menuBarCompanionSettings: MenuBarCompanionSettings = .default

    private let guardService = SystemGuard()
    private let sizer = DirectorySizer()
    private lazy var cleanupScanner = CleanupScanner(guardService: guardService, sizer: sizer)
    private lazy var storageAnalyzer = StorageAnalyzer(guardService: guardService, sizer: sizer)
    private lazy var appInventory = AppInventoryService(guardService: guardService, sizer: sizer)
    private let optimizer = OptimizationService()
    private let privilegedHelper = PrivilegedHelperManager()
    private let menuBarCompanion = MenuBarCompanionManager()
    private let metricsSampler = SystemMetricsSampler()
    private let companionSettingsStore = MenuBarCompanionSettingsStore()
    private var notificationObservers: [NSObjectProtocol] = []

    private var hasLoadedCleanup = false
    private var hasLoadedApplications = false
    private var hasLoadedStorage = false
    private var hasLoadedPrivilegedHelper = false

    private var cleanupRequestID = UUID()
    private var applicationsRequestID = UUID()
    private var storageRequestID = UUID()

    private var cleanupTask: Task<[CleanupCategorySummary], Never>?
    private var applicationsTask: Task<[InstalledApp], Never>?
    private var storageTask: Task<StorageReport, Never>?

    let optimizeActions = OptimizationService.defaultActions
    let privilegedMaintenanceTasks = PrivilegedMaintenanceTask.allCases

    var storageVolumes: [StorageVolume] {
        storageReport?.volumes ?? []
    }

    var selectedStorageVolume: StorageVolume? {
        guard let selectedStorageVolumeID else {
            return nil
        }

        return storageReport?.volumes.first(where: { $0.id == selectedStorageVolumeID })
            ?? storageReport?.hiddenVolumes.first(where: { $0.id == selectedStorageVolumeID })
    }

    var selectedStorageVolumeRequiresManualScan: Bool {
        selectedStorageVolume?.requiresManualScan ?? false
    }

    var selectedStorageVolumeDisplayName: String? {
        selectedStorageVolume?.name
    }

    var smartCareScore: Int {
        let penalty = recommendedActions.reduce(into: 0) { result, action in
            switch action.priority {
            case .urgent:
                result += 18
            case .recommended:
                result += 10
            case .optional:
                result += 4
            }
        }

        return max(0, 100 - penalty)
    }

    var recommendationsByPriority: [(RecommendedActionPriority, [RecommendedAction])] {
        RecommendedActionPriority.allCases.map { priority in
            (priority, recommendedActions.filter { $0.priority == priority })
        }
    }

    var filteredApplications: [InstalledApp] {
        let query = appSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return applications }

        return applications.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var filteredTrashedApplications: [InstalledApp] {
        let query = appSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return trashedApplications }

        return trashedApplications.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var cleanupBytes: UInt64 {
        cleanupCategories.reduce(into: 0) { $0 += $1.totalBytes }
    }

    var uninstallableAppsCount: Int {
        applications.filter { !$0.isProtected }.count
    }

    var quickActions: [MaintenanceQuickAction] {
        [
            MaintenanceQuickAction(id: "refresh-all", title: "Refresh All", subtitle: "Reload cleanup, uninstall, and storage data", icon: "arrow.clockwise"),
            MaintenanceQuickAction(id: "smart-care-report", title: "Export Dry Run", subtitle: "Save a maintenance report to disk", icon: "square.and.arrow.up"),
            MaintenanceQuickAction(id: "hidden-storage", title: "Hidden Space", subtitle: "Switch Storage into hidden-space mode", icon: "eye.slash"),
            MaintenanceQuickAction(id: "admin-storage", title: "Admin Space", subtitle: "Inspect VM, system caches, and backups", icon: "lock.rectangle.stack"),
            MaintenanceQuickAction(id: "review-trash-apps", title: "Review Trash Apps", subtitle: "Preview leftover removal for apps already in Trash", icon: "trash.square"),
            MaintenanceQuickAction(id: "dns", title: "Flush DNS", subtitle: "Run the admin DNS refresh task", icon: "network.badge.shield.half.filled")
        ]
    }

    init() {
        let defaults = UserDefaults.standard
        let lastSelection = defaults.string(forKey: PreferenceKey.lastSelectedSection).flatMap(SidebarSection.init(rawValue:))
        let startupPreference = defaults.string(forKey: PreferenceKey.startupPreference).flatMap(StartupPreference.init(rawValue:)) ?? .rememberLast

        self.startupPreference = startupPreference
        self.selection = startupPreference.resolve(lastSelection: lastSelection)
        self.autoRefreshOnOpen = defaults.object(forKey: PreferenceKey.autoRefreshOnOpen) as? Bool ?? false
        self.menuBarCompanionEnabled = defaults.object(forKey: PreferenceKey.menuBarCompanionEnabled) as? Bool ?? true
        self.showFullDiskAccessReminders = defaults.object(forKey: PreferenceKey.showFullDiskAccessReminders) as? Bool ?? true
        self.storageInspectionMode = defaults.string(forKey: PreferenceKey.storageInspectionMode).flatMap(StorageInspectionMode.init(rawValue:)) ?? .visible
        self.menuBarCompanionSettings = companionSettingsStore.load()

        updateFullDiskAccessBannerVisibility()
        refreshFullDiskAccessStatus()
        menuBarCompanionState = menuBarCompanion.status()
        installExternalOpenObservers()

        metricsSampler.start { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.record(snapshot: snapshot)
            }
        }
    }

    func prepareMainWindow() async {
        syncMenuBarCompanion(launchIfEnabled: menuBarCompanionEnabled)
        refreshFullDiskAccessStatus()
    }

    func prepareSelection() async {
        await loadData(for: selection, force: autoRefreshOnOpen)
    }

    func prepareMenuBar(forceRefresh: Bool = false) async {
        refreshFullDiskAccessStatus()

        if forceRefresh || !hasLoadedCleanup {
            await loadCleanup(force: true)
        }

        if forceRefresh || !hasLoadedApplications {
            await loadApplications(force: true)
        }
    }

    func open(section: SidebarSection) {
        selection = section
    }

    func refreshCurrentSelection() async {
        if selection == .storage {
            await loadStorage(force: true, manuallyScannedVolumeIDs: manualStorageScanTargets)
            return
        }

        await loadData(for: selection, force: true)
    }

    func refreshFromMenuBar() async {
        await prepareMenuBar(forceRefresh: true)

        if storageReport != nil {
            await loadStorage(force: true)
        }
    }

    func refreshCleanup() async {
        await loadCleanup(force: true)
    }

    func trash(_ candidate: CleanupCandidate) async {
        await trashCleanupCandidates([candidate])
    }

    func trashCleanupCandidates(_ candidates: [CleanupCandidate]) async {
        cleanupBusy = true
        cleanupError = nil

        for candidate in candidates where candidate.safetyLevel != .protected {
            do {
                try await guardService.moveToTrash(candidate.url, purpose: .cleanup)
            } catch {
                cleanupError = error.localizedDescription
            }
        }

        await loadCleanup(force: true)
        if hasLoadedStorage {
            await loadStorage(force: true)
        }
    }

    func trash(_ category: CleanupCategorySummary) async {
        await trashCleanupCandidates(category.candidates)
    }

    func refreshApplications() async {
        await loadApplications(force: true)
    }

    func selectApp(_ app: InstalledApp) async {
        selection = .uninstall
        selectedApp = app
        uninstallBusy = true
        uninstallError = nil
        uninstallPreview = await defaultPreview(for: app)
        uninstallBusy = false
    }

    func reviewTrashedApp(_ app: InstalledApp) async {
        selection = .uninstall
        selectedApp = app
        uninstallBusy = true
        uninstallError = nil
        uninstallPreview = await appInventory.previewSmartDelete(for: app)
        uninstallBusy = false
    }

    func previewDefaultRemovalForSelectedApp() async {
        guard let selectedApp else { return }
        uninstallBusy = true
        uninstallError = nil
        uninstallPreview = await defaultPreview(for: selectedApp)
        uninstallBusy = false
    }

    func previewResetForSelectedApp() async {
        guard let selectedApp, !selectedApp.isInTrash else { return }
        uninstallBusy = true
        uninstallError = nil
        uninstallPreview = await appInventory.previewReset(for: selectedApp)
        uninstallBusy = false
    }

    func previewDroppedApplication(at url: URL) async {
        uninstallError = nil
        selection = .uninstall

        guard let app = await appInventory.inspectApplication(at: url) else {
            uninstallError = "Drop an installed .app bundle from /Applications or ~/Applications to preview removal safely."
            return
        }

        mergeApplication(app)
        await selectApp(app)
    }

    func removeSelectedApp() async {
        guard let preview = uninstallPreview else { return }

        uninstallBusy = true
        uninstallError = nil

        do {
            try await appInventory.remove(preview)
            selectedApp = nil
            uninstallPreview = nil

            async let refreshApps: Void = loadApplications(force: true)
            async let refreshCleanup: Void = loadCleanup(force: true)
            async let refreshStorage: Void = hasLoadedStorage ? loadStorage(force: true) : ()
            _ = await (refreshApps, refreshCleanup, refreshStorage)
        } catch {
            uninstallError = error.localizedDescription
        }

        uninstallBusy = false
    }

    func resetSelectedApp() async {
        guard let selectedApp else { return }

        uninstallBusy = true
        uninstallError = nil

        do {
            let preview: UninstallPreview
            if let uninstallPreview, uninstallPreview.app.id == selectedApp.id, uninstallPreview.mode == .resetApp {
                preview = uninstallPreview
            } else {
                preview = await appInventory.previewReset(for: selectedApp)
            }
            try await appInventory.remove(preview)
            uninstallPreview = await defaultPreview(for: selectedApp)
            await loadCleanup(force: true)
            if hasLoadedStorage {
                await loadStorage(force: true)
            }
        } catch {
            uninstallError = error.localizedDescription
        }

        uninstallBusy = false
    }

    func reviewFirstTrashedApplication() async {
        guard let app = trashedApplications.first else { return }
        await reviewTrashedApp(app)
    }

    func setStorageInspectionMode(_ mode: StorageInspectionMode) {
        storageInspectionMode = mode
        selection = .storage

        guard let storageReport else { return }

        switch mode {
        case .visible:
            if let selectedStorageVolumeID,
               let volume = storageReport.volumes.first(where: { $0.id == selectedStorageVolumeID }) {
                focusStorageVolume(volume)
            } else if let firstVolume = storageReport.volumes.first {
                focusStorageVolume(firstVolume)
            }
        case .hidden:
            if let selectedStorageVolumeID,
               let volume = storageReport.hiddenVolumes.first(where: { $0.id == selectedStorageVolumeID }) {
                focusStorageVolume(volume)
            } else if let firstHiddenVolume = storageReport.hiddenVolumes.first {
                focusStorageVolume(firstHiddenVolume)
            } else {
                selectedStorageVolumeID = nil
                storageVolumeCurrentNode = nil
                storageVolumeBreadcrumb = []
            }
        case .admin:
            selectedStorageVolumeID = nil
            storageVolumeCurrentNode = nil
            storageVolumeBreadcrumb = []
        }
    }

    func performQuickAction(_ action: MaintenanceQuickAction) async {
        switch action.id {
        case "refresh-all":
            await refreshSmartCareInputs()
        case "smart-care-report":
            await exportDryRunReport()
        case "hidden-storage":
            setStorageInspectionMode(.hidden)
        case "admin-storage":
            setStorageInspectionMode(.admin)
        case "review-trash-apps":
            await reviewFirstTrashedApplication()
        case "dns":
            if privilegedHelperState.isEnabled {
                await runPrivilegedMaintenance(.flushDNSCache)
            } else {
                selection = .optimize
            }
        default:
            break
        }
    }

    func refreshStorage() async {
        await loadStorage(force: true, manuallyScannedVolumeIDs: manualStorageScanTargets)
    }

    func focusStorageVolume(_ volume: StorageVolume) {
        selectedStorageVolumeID = volume.id
        storageVolumeCurrentNode = volume.browserRoot
        storageVolumeBreadcrumb = [volume.browserRoot]
        storageVolumeError = volume.requiresManualScan
            ? "This volume is listed immediately, but SK Mole waits for a manual scan before building its folder map."
            : nil
    }

    func drillIntoStorageNode(_ node: StorageNode) async {
        guard node.isDrillable, let url = node.url else {
            if let url = node.url {
                reveal(url)
            }
            return
        }

        storageVolumeBusy = true
        storageVolumeError = nil

        let browsed = await storageAnalyzer.browseNode(
            at: url,
            displayName: node.name,
            knownSize: node.sizeBytes,
            icon: node.icon,
            kindHint: node.kind
        )

        if let existingIndex = storageVolumeBreadcrumb.firstIndex(where: { $0.id == node.id }) {
            storageVolumeBreadcrumb = Array(storageVolumeBreadcrumb.prefix(existingIndex)) + [browsed]
        } else {
            storageVolumeBreadcrumb.append(browsed)
        }

        storageVolumeCurrentNode = browsed
        storageVolumeBusy = false
    }

    func selectStorageBreadcrumb(_ node: StorageNode) {
        guard let index = storageVolumeBreadcrumb.firstIndex(where: { $0.id == node.id }) else {
            return
        }

        storageVolumeBreadcrumb = Array(storageVolumeBreadcrumb.prefix(index + 1))
        storageVolumeCurrentNode = storageVolumeBreadcrumb.last
    }

    func canTrashFromStorage(_ file: LargeFileEntry) -> Bool {
        let normalized = URLPathSafety.standardized(file.url)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let homeApplications = home.appendingPathComponent("Applications")

        guard URLPathSafety.isDescendant(normalized, of: home) else {
            return false
        }

        if URLPathSafety.isDescendant(normalized, of: homeApplications) {
            return false
        }

        if normalized.pathExtension.lowercased() == "app" {
            return false
        }

        return !normalized.pathComponents.dropLast().contains(where: { $0.lowercased().hasSuffix(".app") })
    }

    func trashStorageFile(_ file: LargeFileEntry) async {
        storageBusy = true
        storageError = nil

        do {
            try await guardService.moveToTrash(file.url, purpose: .storage)
            await loadStorage(force: true)
        } catch {
            storageError = error.localizedDescription
            storageBusy = false
        }
    }

    func trashStorageFiles(_ files: [LargeFileEntry]) async {
        storageBusy = true
        storageError = nil

        for file in files {
            do {
                try await guardService.moveToTrash(file.url, purpose: .storage)
            } catch {
                storageError = error.localizedDescription
            }
        }

        await loadStorage(force: true)
    }

    func runOptimization(_ action: OptimizeActionDescriptor) async {
        optimizationBusyActionID = action.id
        let result = await optimizer.run(action)
        optimizationLogs.insert(result, at: 0)
        optimizationBusyActionID = nil
    }

    func refreshPrivilegedHelperState() async {
        privilegedHelperError = nil
        privilegedHelperState = privilegedHelper.status()

        guard privilegedHelperState.isEnabled else {
            privilegedHelperReachability = privilegedHelperState.requiresApproval ? "Awaiting approval" : "Unavailable"
            hasLoadedPrivilegedHelper = true
            updateRecommendedActions()
            return
        }

        do {
            privilegedHelperReachability = try await privilegedHelper.ping()
        } catch {
            privilegedHelperReachability = "Unavailable"
            privilegedHelperError = error.localizedDescription
        }

        hasLoadedPrivilegedHelper = true
        updateRecommendedActions()
    }

    func registerPrivilegedHelper() async {
        privilegedHelperBusy = true
        privilegedHelperError = nil

        do {
            privilegedHelperState = try privilegedHelper.register()
            await refreshPrivilegedHelperState()
        } catch {
            privilegedHelperError = error.localizedDescription
        }

        privilegedHelperBusy = false
    }

    func unregisterPrivilegedHelper() async {
        privilegedHelperBusy = true
        privilegedHelperError = nil

        do {
            privilegedHelperState = try privilegedHelper.unregister()
            await refreshPrivilegedHelperState()
        } catch {
            privilegedHelperError = error.localizedDescription
        }

        privilegedHelperBusy = false
    }

    func runPrivilegedMaintenance(_ task: PrivilegedMaintenanceTask) async {
        privilegedHelperBusyTaskID = task.id
        privilegedHelperError = nil

        do {
            let output = try await privilegedHelper.run(task)
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Admin: \(task.title)",
                    output: output,
                    succeeded: true,
                    timestamp: .now
                ),
                at: 0
            )
            await refreshPrivilegedHelperState()
        } catch {
            privilegedHelperError = error.localizedDescription
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Admin: \(task.title)",
                    output: error.localizedDescription,
                    succeeded: false,
                    timestamp: .now
                ),
                at: 0
            )
        }

        privilegedHelperBusyTaskID = nil
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFolder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func openFullDiskAccessSettings() {
        let privacySecurityURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")
        let settingsApp = URL(fileURLWithPath: "/System/Applications/System Settings.app")

        if let privacySecurityURL, NSWorkspace.shared.open(privacySecurityURL) {
            return
        }

        NSWorkspace.shared.open(settingsApp)
    }

    func handleIncomingURL(_ url: URL) async {
        guard url.scheme?.lowercased() == MenuBarHelperConstants.mainAppURLScheme else {
            return
        }

        if url.host?.lowercased() == "section" {
            let slug = url.pathComponents.dropFirst().first?.lowercased()
            if let slug, let section = SidebarSection(urlSlug: slug) {
                open(section: section)
            }
            return
        }
    }

    func dismissFullDiskAccessBanner() {
        showFullDiskAccessReminders = false
    }

    func restoreFullDiskAccessReminder() {
        showFullDiskAccessReminders = true
    }

    func launchMenuBarCompanionNow() {
        menuBarCompanion.launchIfNeeded()
        refreshMenuBarCompanionState()
    }

    func quitMenuBarCompanion() {
        menuBarCompanion.terminateRunningHelper()
        refreshMenuBarCompanionState()
    }

    func refreshMenuBarCompanionState() {
        menuBarCompanionState = menuBarCompanion.status(registrationError: menuBarCompanionError)
        updateRecommendedActions()
    }

    func saveMenuBarCompanionSettings(_ update: (inout MenuBarCompanionSettings) -> Void) {
        var revised = menuBarCompanionSettings
        update(&revised)
        menuBarCompanionSettings = revised

        do {
            try companionSettingsStore.save(revised)
            menuBarCompanionError = nil
        } catch {
            menuBarCompanionError = error.localizedDescription
        }
    }

    func resetMenuBarCompanionSettings() {
        menuBarCompanionSettings = .default

        do {
            try companionSettingsStore.save(.default)
            menuBarCompanionError = nil
        } catch {
            menuBarCompanionError = error.localizedDescription
        }
    }

    func refreshSmartCareInputs() async {
        async let refreshCleanup: Void = loadCleanup(force: true)
        async let refreshApplications: Void = loadApplications(force: true)
        async let refreshStorage: Void = loadStorage(force: true)
        _ = await (refreshCleanup, refreshApplications, refreshStorage)
    }

    func exportDryRunReport() async {
        let report = maintenanceReport()
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: report.createdAt).replacingOccurrences(of: ":", with: "-")
        let fileName = "SK-Mole-Dry-Run-\(timestamp).json"

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(report) else {
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = fileName
        panel.allowedContentTypes = [UTType.json]
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")

        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        do {
            try data.write(to: destination, options: .atomic)
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Export Dry Run Report",
                    output: "Saved maintenance report to \(destination.path)",
                    succeeded: true,
                    timestamp: .now
                ),
                at: 0
            )
        } catch {
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Export Dry Run Report",
                    output: error.localizedDescription,
                    succeeded: false,
                    timestamp: .now
                ),
                at: 0
            )
        }
    }

    func performRecommendedAction(_ recommendation: RecommendedAction) async {
        switch recommendation.intent {
        case .openSection(let section):
            open(section: section)
        case .trashCleanupCategory(let categoryID):
            if let category = cleanupCategories.first(where: { $0.category == categoryID }) {
                selection = .cleanup
                await trash(category)
            }
        case .previewApplication(let appID):
            if let app = applications.first(where: { $0.id == appID }) {
                await selectApp(app)
            }
        case .previewTrashedApplication(let appID):
            if let app = trashedApplications.first(where: { $0.id == appID }) {
                await reviewTrashedApp(app)
            }
        case .resetApplication(let appID):
            if let app = applications.first(where: { $0.id == appID }) {
                await selectApp(app)
                await previewResetForSelectedApp()
            }
        case .focusVolume(let volumeID):
            if let volume = storageReport?.volumes.first(where: { $0.id == volumeID }) {
                selection = .storage
                focusStorageVolume(volume)
            }
        case .setStorageMode(let mode):
            setStorageInspectionMode(mode)
        case .revealURL(let url):
            reveal(url)
        case .openFullDiskAccess:
            openFullDiskAccessSettings()
        case .exportDryRunReport:
            await exportDryRunReport()
        case .runPrivilegedTask(let task):
            selection = .optimize
            await runPrivilegedMaintenance(task)
        }
    }

    func refreshFullDiskAccessStatus() {
        Task {
            let status = await Task.detached(priority: .utility) {
                Self.detectFullDiskAccessStatus()
            }.value

            await MainActor.run {
                self.fullDiskAccessStatus = status
                self.updateRecommendedActions()
            }
        }
    }

    private func loadData(for section: SidebarSection, force: Bool) async {
        switch section {
        case .dashboard:
            if force || !hasLoadedCleanup {
                await loadCleanup(force: true)
            }

            if force || !hasLoadedApplications {
                await loadApplications(force: true)
            }

            if force || !hasLoadedStorage {
                await loadStorage(force: true)
            }
        case .smartCare:
            let shouldRefreshCleanup = force || !hasLoadedCleanup
            let shouldRefreshApplications = force || !hasLoadedApplications
            let shouldRefreshStorage = force || !hasLoadedStorage
            async let refreshCleanup: Void = loadCleanup(force: shouldRefreshCleanup)
            async let refreshApplications: Void = loadApplications(force: shouldRefreshApplications)
            async let refreshStorage: Void = loadStorage(force: shouldRefreshStorage)
            _ = await (refreshCleanup, refreshApplications, refreshStorage)
        case .cleanup:
            await loadCleanup(force: force || !hasLoadedCleanup)
        case .uninstall:
            await loadApplications(force: force || !hasLoadedApplications)
        case .storage:
            await loadStorage(force: force || !hasLoadedStorage)
        case .optimize:
            if force || !hasLoadedPrivilegedHelper {
                await refreshPrivilegedHelperState()
            }
        }
    }

    private func loadCleanup(force: Bool) async {
        guard force || !hasLoadedCleanup else {
            return
        }

        cleanupTask?.cancel()
        let requestID = UUID()
        cleanupRequestID = requestID

        cleanupBusy = true
        cleanupError = nil
        cleanupProgress = ScanProgress(
            title: "Cleanup scan",
            detail: "Preparing cleanup scan",
            completedUnits: 0,
            totalUnits: 1
        )

        let scanner = cleanupScanner
        let task = Task { [requestID] in
            await scanner.scan { progress in
                await MainActor.run {
                    guard self.cleanupRequestID == requestID else { return }
                    self.cleanupProgress = progress
                }
            }
        }
        cleanupTask = task

        let results = await task.value
        guard cleanupRequestID == requestID else { return }

        cleanupCategories = results
        cleanupBusy = false
        cleanupProgress = nil
        cleanupTask = nil
        hasLoadedCleanup = true
        updateRecommendedActions()
    }

    private func loadApplications(force: Bool) async {
        guard force || !hasLoadedApplications else {
            return
        }

        applicationsTask?.cancel()
        let requestID = UUID()
        applicationsRequestID = requestID

        uninstallBusy = true
        uninstallError = nil
        applicationDiscoveryProgress = ScanProgress(
            title: "App inventory",
            detail: "Discovering installed apps",
            completedUnits: 0,
            totalUnits: 1
        )

        let inventory = appInventory
        let task = Task { [requestID] in
            await inventory.discoverApplications { progress in
                await MainActor.run {
                    guard self.applicationsRequestID == requestID else { return }
                    self.applicationDiscoveryProgress = progress
                }
            }
        }
        applicationsTask = task

        let discovered = await task.value
        guard applicationsRequestID == requestID else { return }

        let trashed = await inventory.discoverTrashedApplications()
        guard applicationsRequestID == requestID else { return }

        applications = discovered
        trashedApplications = trashed
        uninstallBusy = false
        applicationDiscoveryProgress = nil
        applicationsTask = nil
        hasLoadedApplications = true

        if let selectedApp {
            if let refreshedSelection = (applications + trashedApplications).first(where: { $0.id == selectedApp.id }) {
                self.selectedApp = refreshedSelection
            } else {
                self.selectedApp = nil
                self.uninstallPreview = nil
            }
        }

        updateRecommendedActions()
    }

    private func loadStorage(force: Bool) async {
        await loadStorage(force: force, manuallyScannedVolumeIDs: [])
    }

    private var manualStorageScanTargets: Set<String> {
        guard let selectedStorageVolume, selectedStorageVolume.requiresManualScan else {
            return []
        }

        return [selectedStorageVolume.id]
    }

    private func loadStorage(force: Bool, manuallyScannedVolumeIDs: Set<String>) async {
        guard force || !hasLoadedStorage else {
            return
        }

        storageTask?.cancel()
        let requestID = UUID()
        storageRequestID = requestID

        storageBusy = true
        storageError = nil
        storageProgress = ScanProgress(
            title: "Storage scan",
            detail: "Preparing storage scan",
            completedUnits: 0,
            totalUnits: 1
        )

        let analyzer = storageAnalyzer
        let task = Task { [requestID] in
            await analyzer.scan(manuallyScannedVolumeIDs: manuallyScannedVolumeIDs) { progress in
                await MainActor.run {
                    guard self.storageRequestID == requestID else { return }
                    self.storageProgress = progress
                }
            }
        }
        storageTask = task

        let report = await task.value
        guard storageRequestID == requestID else { return }

        storageReport = report
        storageBusy = false
        storageProgress = nil
        storageTask = nil
        hasLoadedStorage = true

        if let selectedStorageVolumeID,
           let existing = (report.volumes + report.hiddenVolumes).first(where: { $0.id == selectedStorageVolumeID }) {
            focusStorageVolume(existing)
        } else if storageInspectionMode == .hidden, let firstHiddenVolume = report.hiddenVolumes.first {
            focusStorageVolume(firstHiddenVolume)
        } else if let firstVolume = report.volumes.first {
            focusStorageVolume(firstVolume)
        } else {
            selectedStorageVolumeID = nil
            storageVolumeCurrentNode = nil
            storageVolumeBreadcrumb = []
        }

        updateRecommendedActions()
    }

    private func record(snapshot: SystemMetricSnapshot) {
        metrics = snapshot
        cpuHistory = appendHistory(cpuHistory, value: snapshot.cpuUsage, date: snapshot.timestamp)
        memoryHistory = appendHistory(memoryHistory, value: snapshot.memoryUsage, date: snapshot.timestamp)
        downloadHistory = appendHistory(downloadHistory, value: Double(snapshot.networkDownloadRate), date: snapshot.timestamp)
        uploadHistory = appendHistory(uploadHistory, value: Double(snapshot.networkUploadRate), date: snapshot.timestamp)
        updateRecommendedActions()
    }

    private func appendHistory(_ points: [MetricHistoryPoint], value: Double, date: Date) -> [MetricHistoryPoint] {
        var updated = points
        updated.append(MetricHistoryPoint(timestamp: date, value: value))

        if updated.count > HistoryLimit.points {
            updated.removeFirst(updated.count - HistoryLimit.points)
        }

        return updated
    }

    private func updateFullDiskAccessBannerVisibility() {
        showFullDiskAccessBanner = showFullDiskAccessReminders && fullDiskAccessStatus.needsAttention
    }

    private func syncMenuBarCompanion(launchIfEnabled: Bool) {
        menuBarCompanionError = nil

        if launchIfEnabled {
            menuBarCompanion.launchIfNeeded()

            do {
                try menuBarCompanion.registerForLaunchAtLogin()
            } catch {
                menuBarCompanionError = error.localizedDescription
            }
        } else {
            do {
                try menuBarCompanion.unregisterFromLaunchAtLogin()
            } catch {
                menuBarCompanionError = error.localizedDescription
            }

            menuBarCompanion.terminateRunningHelper()
        }

        refreshMenuBarCompanionState()
    }

    private func mergeApplication(_ app: InstalledApp) {
        var merged = applications.filter { $0.id != app.id }
        merged.append(app)
        applications = merged.sorted {
            let nameComparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            return $0.url.path.localizedCaseInsensitiveCompare($1.url.path) == .orderedAscending
        }

        updateRecommendedActions()
    }

    private func defaultPreview(for app: InstalledApp) async -> UninstallPreview {
        if app.isInTrash {
            return await appInventory.previewSmartDelete(for: app)
        }

        return await appInventory.previewRemoval(for: app)
    }

    private func maintenanceReport() -> MaintenanceReport {
        let cleanupSummary = cleanupCategories
            .filter { !$0.candidates.isEmpty }
            .map { "\($0.title): \(ByteFormatting.format($0.totalBytes)) across \($0.candidates.count) item\($0.candidates.count == 1 ? "" : "s")" }

        let recommendationSummary = recommendedActions.prefix(8).map { "\($0.title): \($0.subtitle)" }
        let trashedAppSummary = trashedApplications.prefix(12).map { "\($0.name) (\(ByteFormatting.format($0.sizeBytes)))" }
        let alertSummary = menuBarCompanionSettings.rules
            .filter(\.isEnabled)
            .map(\.summary)

        return MaintenanceReport(
            createdAt: .now,
            score: smartCareScore,
            fullDiskAccessStatus: fullDiskAccessStatus.title,
            cleanupBytes: cleanupBytes,
            cleanupCategories: cleanupSummary,
            topRecommendations: recommendationSummary,
            storageSummary: storageSummaryLines(),
            trashedApps: trashedAppSummary,
            menuBarAlerts: alertSummary
        )
    }

    private func installExternalOpenObservers() {
        let token = NotificationCenter.default.addObserver(
            forName: .skmoleOpenURLs,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let urls = notification.userInfo?["urls"] as? [URL]
            else {
                return
            }

            Task { @MainActor in
                await self.handleOpenedFileURLs(urls)
            }
        }

        notificationObservers.append(token)
    }

    private func handleOpenedFileURLs(_ urls: [URL]) async {
        guard let firstApplication = urls.first(where: { $0.pathExtension.lowercased() == "app" }) else {
            return
        }

        await previewDroppedApplication(at: firstApplication)
    }

    private func updateRecommendedActions() {
        var actions: [RecommendedAction] = []

        if fullDiskAccessStatus.needsAttention {
            actions.append(
                RecommendedAction(
                    id: "full-disk-access",
                    title: "Unlock deeper scans",
                    subtitle: "Full Disk Access is still limited.",
                    detail: "Granting one broader permission removes repeated folder prompts and lets storage scans explain more of the startup disk safely.",
                    icon: "lock.shield",
                    priority: .recommended,
                    callToAction: "Open Settings",
                    intent: .openFullDiskAccess
                )
            )
        }

        if let startupVolume = storageReport?.volumes.first(where: { $0.kind == .startup }), startupVolume.freeRatio < 0.12 {
            let detail = "The startup disk is down to \(Int((startupVolume.freeRatio * 100).rounded()))% free. Clearing purgeable space or reclaiming review items now will help avoid pressure spikes."
            actions.append(
                RecommendedAction(
                    id: "startup-volume-pressure",
                    title: "Low free space on startup disk",
                    subtitle: "\(ByteFormatting.format(startupVolume.availableBytes)) free on \(startupVolume.name)",
                    detail: detail,
                    icon: startupVolume.kind.symbol,
                    priority: .urgent,
                    estimatedImpactBytes: startupVolume.availableBytes,
                    callToAction: privilegedHelperState.isEnabled ? "Free Purgeable Space" : "Open Storage",
                    intent: privilegedHelperState.isEnabled ? .runPrivilegedTask(.freePurgeableSpace) : .focusVolume(startupVolume.id)
                )
            )
        }

        if let hiddenInsight = storageReport?.hiddenInsights
            .sorted(by: { $0.sizeBytes > $1.sizeBytes })
            .first(where: { $0.sizeBytes >= 8 * 1_024 * 1_024 * 1_024 }) {
            actions.append(
                RecommendedAction(
                    id: "hidden-space-\(hiddenInsight.id)",
                    title: "Inspect hidden space",
                    subtitle: hiddenInsight.title,
                    detail: hiddenInsight.detail,
                    icon: hiddenInsight.icon,
                    priority: .recommended,
                    estimatedImpactBytes: hiddenInsight.sizeBytes,
                    callToAction: "Open Hidden Space",
                    intent: .setStorageMode(.hidden)
                )
            )
        }

        if let adminInsight = storageReport?.adminInsights
            .sorted(by: { $0.sizeBytes > $1.sizeBytes })
            .first(where: { $0.sizeBytes >= 2 * 1_024 * 1_024 * 1_024 }) {
            actions.append(
                RecommendedAction(
                    id: "admin-space-\(adminInsight.id)",
                    title: "Review admin-only storage",
                    subtitle: adminInsight.title,
                    detail: adminInsight.detail,
                    icon: adminInsight.icon,
                    priority: .optional,
                    estimatedImpactBytes: adminInsight.sizeBytes,
                    callToAction: "Open Admin Scan",
                    intent: .setStorageMode(.admin)
                )
            )
        }

        for category in cleanupCategories.sorted(by: { $0.totalBytes > $1.totalBytes }).prefix(4) where category.totalBytes >= 768 * 1_024 * 1_024 {
            let priority: RecommendedActionPriority = category.safetyLevel == .safe ? .recommended : .optional
            let callToAction = category.safetyLevel == .safe ? "Clean Now" : "Review in Cleanup"
            let intent: RecommendedActionIntent = category.safetyLevel == .safe ? .trashCleanupCategory(category.category) : .openSection(.cleanup)

            actions.append(
                RecommendedAction(
                    id: "cleanup-\(category.id.rawValue)",
                    title: "Reclaim \(category.title.lowercased())",
                    subtitle: ByteFormatting.format(category.totalBytes),
                    detail: category.subtitle,
                    icon: category.icon,
                    priority: priority,
                    estimatedImpactBytes: category.totalBytes,
                    callToAction: callToAction,
                    intent: intent
                )
            )
        }

        if let duplicateCategory = cleanupCategories.first(where: { $0.category == .duplicates && $0.totalBytes > 0 }) {
            actions.append(
                RecommendedAction(
                    id: "duplicates-review",
                    title: "Review duplicate files",
                    subtitle: ByteFormatting.format(duplicateCategory.totalBytes),
                    detail: "SK Mole found likely duplicates in common user folders and kept one likely-primary copy. Review the extras before moving them to Trash.",
                    icon: duplicateCategory.icon,
                    priority: .recommended,
                    estimatedImpactBytes: duplicateCategory.totalBytes,
                    callToAction: "Open Cleanup",
                    intent: .openSection(.cleanup)
                )
            )
        }

        if let installerCategory = cleanupCategories.first(where: { $0.category == .installers && $0.totalBytes > 0 }) {
            actions.append(
                RecommendedAction(
                    id: "installers-review",
                    title: "Clear stale installers",
                    subtitle: ByteFormatting.format(installerCategory.totalBytes),
                    detail: "Disk images and package installers often linger long after an install is finished. Review them in Cleanup before reclaiming the space.",
                    icon: installerCategory.icon,
                    priority: .recommended,
                    estimatedImpactBytes: installerCategory.totalBytes,
                    callToAction: "Open Cleanup",
                    intent: .openSection(.cleanup)
                )
            )
        }

        if let downloadsCategory = cleanupCategories.first(where: { $0.category == .oldDownloads && $0.totalBytes > 0 }) {
            actions.append(
                RecommendedAction(
                    id: "old-downloads-review",
                    title: "Review old downloads",
                    subtitle: ByteFormatting.format(downloadsCategory.totalBytes),
                    detail: "SK Mole found large downloads that have been untouched for over 45 days. This is usually one of the quickest manual wins.",
                    icon: downloadsCategory.icon,
                    priority: .optional,
                    estimatedImpactBytes: downloadsCategory.totalBytes,
                    callToAction: "Open Cleanup",
                    intent: .openSection(.cleanup)
                )
            )
        }

        if let largeFile = storageReport?.largeFiles.first(where: { !$0.isAppBundle && canTrashFromStorage($0) }) {
            actions.append(
                RecommendedAction(
                    id: "large-file-\(largeFile.id)",
                    title: "Review oversized file",
                    subtitle: largeFile.displayName,
                    detail: "A single item is using \(ByteFormatting.format(largeFile.sizeBytes)). The Storage browser can reveal it instantly before you decide what to do.",
                    icon: "doc.badge.magnifyingglass",
                    priority: .recommended,
                    estimatedImpactBytes: largeFile.sizeBytes,
                    callToAction: "Open Storage",
                    intent: .openSection(.storage)
                )
            )
        }

        if let trashedApp = trashedApplications.sorted(by: { $0.sizeBytes > $1.sizeBytes }).first {
            actions.append(
                RecommendedAction(
                    id: "smart-delete-\(trashedApp.id)",
                    title: "Finish uninstall from Trash",
                    subtitle: trashedApp.name,
                    detail: "This app is already in Trash. SK Mole can run a SmartDelete-style leftover review and show any user-domain support files still outside Trash.",
                    icon: "trash.square",
                    priority: .recommended,
                    estimatedImpactBytes: trashedApp.sizeBytes,
                    callToAction: "Review Trash App",
                    intent: .previewTrashedApplication(trashedApp.id)
                )
            )
        }

        if let removableApp = applications
            .filter({ !$0.isProtected })
            .sorted(by: { $0.sizeBytes > $1.sizeBytes })
            .first(where: { $0.sizeBytes >= 2 * 1_024 * 1_024 * 1_024 }) {
            actions.append(
                RecommendedAction(
                    id: "app-review-\(removableApp.id)",
                    title: "Preview a large app uninstall",
                    subtitle: removableApp.name,
                    detail: "This app occupies \(ByteFormatting.format(removableApp.sizeBytes)). SK Mole can preview its user-domain remnants before anything moves to Trash.",
                    icon: "xmark.app",
                    priority: .optional,
                    estimatedImpactBytes: removableApp.sizeBytes,
                    callToAction: "Preview Uninstall",
                    intent: .previewApplication(removableApp.id)
                )
            )
        }

        if let resetCandidate = applications
            .filter({ !$0.isProtected && !$0.isRunning })
            .sorted(by: { $0.sizeBytes > $1.sizeBytes })
            .first(where: { $0.sizeBytes >= 1 * 1_024 * 1_024 * 1_024 }) {
            actions.append(
                RecommendedAction(
                    id: "app-reset-\(resetCandidate.id)",
                    title: "Preview an app reset",
                    subtitle: resetCandidate.name,
                    detail: "When an app is misbehaving, a reset can clear user-domain support files without removing the app bundle itself. SK Mole can preview that path first.",
                    icon: "arrow.counterclockwise.circle",
                    priority: .optional,
                    estimatedImpactBytes: resetCandidate.sizeBytes,
                    callToAction: "Preview Reset",
                    intent: .resetApplication(resetCandidate.id)
                )
            )
        }

        if metrics.memoryPressure == .high || metrics.thermalState == .serious || metrics.thermalState == .critical {
            actions.append(
                RecommendedAction(
                    id: "system-pressure",
                    title: "Mac is under pressure right now",
                    subtitle: "\(metrics.memoryPressure.title) memory pressure • \(metrics.thermalState.title) thermal state",
                    detail: "SK Mole is seeing system strain from public macOS signals. Clearing space or pausing heavy work may help the Mac recover faster.",
                    icon: "waveform.path.ecg",
                    priority: .urgent,
                    callToAction: "Open Dashboard",
                    intent: .openSection(.dashboard)
                )
            )
        }

        if hasLoadedCleanup || hasLoadedApplications || hasLoadedStorage {
            actions.append(
                RecommendedAction(
                    id: "export-dry-run",
                    title: "Export a dry-run maintenance report",
                    subtitle: "Snapshot the current findings before you clean or uninstall anything.",
                    detail: "The report captures cleanup estimates, storage context, recommendations, trashed-app review targets, and active menu bar alert rules.",
                    icon: "square.and.arrow.up",
                    priority: .optional,
                    callToAction: "Export Report",
                    intent: .exportDryRunReport
                )
            )
        }

        recommendedActions = Array(
            actions
                .reduce(into: [String: RecommendedAction]()) { partial, action in
                    partial[action.id] = action
                }
                .values
        )
        .sorted { left, right in
            if left.priority != right.priority {
                return priorityRank(left.priority) < priorityRank(right.priority)
            }

            return (left.estimatedImpactBytes ?? 0) > (right.estimatedImpactBytes ?? 0)
        }
    }

    private func storageSummaryLines() -> [String] {
        var lines: [String] = []

        if let storageReport {
            lines.append("Visible tracked storage: \(ByteFormatting.format(storageReport.totalTrackedBytes))")

            if let startupVolume = storageReport.volumes.first(where: { $0.kind == .startup }) {
                lines.append("Startup disk free: \(ByteFormatting.format(startupVolume.availableBytes)) of \(ByteFormatting.format(startupVolume.totalBytes))")
            }

            let hiddenBytes = storageReport.hiddenInsights.reduce(into: UInt64(0)) { $0 += $1.sizeBytes }
            if hiddenBytes > 0 {
                lines.append("Hidden-space findings: \(ByteFormatting.format(hiddenBytes))")
            }

            let adminBytes = storageReport.adminInsights.reduce(into: UInt64(0)) { $0 += $1.sizeBytes }
            if adminBytes > 0 {
                lines.append("Admin-path findings: \(ByteFormatting.format(adminBytes))")
            }
        } else {
            lines.append("Storage scan has not been run yet.")
        }

        lines.append("Current inspection mode: \(storageInspectionMode.title)")
        return lines
    }

    private func priorityRank(_ priority: RecommendedActionPriority) -> Int {
        switch priority {
        case .urgent: 0
        case .recommended: 1
        case .optional: 2
        }
    }

    nonisolated private static func detectFullDiskAccessStatus() -> FullDiskAccessStatus {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let probes = [
            home.appendingPathComponent("Library/Mail"),
            home.appendingPathComponent("Library/Safari"),
            home.appendingPathComponent("Library/Messages")
        ]

        var foundProtectedLocation = false

        for url in probes {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            foundProtectedLocation = true

            do {
                _ = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                return .granted
            } catch {
                continue
            }
        }

        return foundProtectedLocation ? .limited : .unknown
    }
}

extension Notification.Name {
    static let skmoleOpenURLs = Notification.Name("SKMole.OpenURLs")
}
