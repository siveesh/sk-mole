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
        static let hasCompletedOnboarding = "skmole.hasCompletedOnboarding"
        static let uninstallSensitivity = "skmole.uninstallSensitivity"
        static let storageInspectionMode = "skmole.storageInspectionMode"
        static let storageFocusMode = "skmole.storageFocusMode"
        static let storageMinimumSize = "skmole.storageMinimumSize"
        static let storageCollapseClutter = "skmole.storageCollapseClutter"
        static let magikaRecursiveDirectories = "skmole.magikaRecursiveDirectories"
        static let networkResolveHostnames = "skmole.networkResolveHostnames"
        static let networkIncludeListeningSockets = "skmole.networkIncludeListeningSockets"
        static let processSortMode = "skmole.processSortMode"
        static let scheduledMaintenanceInterval = "skmole.scheduledMaintenanceInterval"
        static let scheduledMaintenanceFormat = "skmole.scheduledMaintenanceFormat"
        static let scheduledMaintenanceLastRun = "skmole.scheduledMaintenanceLastRun"
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

    @Published var menuBarCompanionEnabled = false {
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

    @Published var showOnboarding = false
    @Published var hasCompletedOnboarding = false

    @Published var applications: [InstalledApp] = []
    @Published var trashedApplications: [InstalledApp] = []
    @Published var appSearch = ""
    @Published var uninstallSensitivity: UninstallSensitivityLevel = .enhanced {
        didSet {
            UserDefaults.standard.set(uninstallSensitivity.rawValue, forKey: PreferenceKey.uninstallSensitivity)
        }
    }
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
    @Published var storageFocusMode: StorageFocusMode = .balanced {
        didSet {
            UserDefaults.standard.set(storageFocusMode.rawValue, forKey: PreferenceKey.storageFocusMode)
        }
    }
    @Published var storageMinimumSize: StorageMinimumSizeFilter = .all {
        didSet {
            UserDefaults.standard.set(storageMinimumSize.rawValue, forKey: PreferenceKey.storageMinimumSize)
        }
    }
    @Published var storageCollapseCommonClutter = true {
        didSet {
            UserDefaults.standard.set(storageCollapseCommonClutter, forKey: PreferenceKey.storageCollapseClutter)
        }
    }
    @Published var selectedStorageVolumeID: String?
    @Published var storageVolumeCurrentNode: StorageNode?
    @Published var storageVolumeBreadcrumb: [StorageNode] = []
    @Published var storageVolumeBusy = false
    @Published var storageVolumeError: String?

    @Published var networkReport: NetworkInspectorReport?
    @Published var networkBusy = false
    @Published var networkError: String?
    @Published var networkResolveHostnames = false {
        didSet {
            UserDefaults.standard.set(networkResolveHostnames, forKey: PreferenceKey.networkResolveHostnames)
        }
    }
    @Published var networkIncludeListeningSockets = true {
        didSet {
            UserDefaults.standard.set(networkIncludeListeningSockets, forKey: PreferenceKey.networkIncludeListeningSockets)
        }
    }

    @Published var processInspectorItems: [NativeProcessActivity] = []
    @Published var processInspectorBusy = false
    @Published var processInspectorError: String?
    @Published var processSearch = ""
    @Published var processSortMode: ProcessSortMode = .cpu {
        didSet {
            UserDefaults.standard.set(processSortMode.rawValue, forKey: PreferenceKey.processSortMode)
        }
    }
    @Published var processTerminationBusyPID: Int32?

    @Published var scheduledMaintenanceInterval: ScheduledMaintenanceInterval = .off {
        didSet {
            UserDefaults.standard.set(scheduledMaintenanceInterval.rawValue, forKey: PreferenceKey.scheduledMaintenanceInterval)
        }
    }
    @Published var scheduledMaintenanceExportFormat: ScheduledMaintenanceExportFormat = .markdown {
        didSet {
            UserDefaults.standard.set(scheduledMaintenanceExportFormat.rawValue, forKey: PreferenceKey.scheduledMaintenanceFormat)
        }
    }
    @Published var lastScheduledMaintenanceRun: Date? {
        didSet {
            UserDefaults.standard.set(lastScheduledMaintenanceRun, forKey: PreferenceKey.scheduledMaintenanceLastRun)
        }
    }

    @Published var quarantinedApplications: [QuarantinedApplication] = []
    @Published var quarantineBusy = false
    @Published var quarantineError: String?
    @Published var quarantineProgress: ScanProgress?
    @Published var quarantineSearch = ""
    @Published var selectedQuarantinedApp: QuarantinedApplication?
    @Published var quarantineBusyActionID: String?
    @Published var quarantineLogs: [OptimizationLog] = []

    @Published var homebrewInventory: HomebrewInventory?
    @Published var homebrewBusy = false
    @Published var homebrewSearchBusy = false
    @Published var homebrewDetailBusy = false
    @Published var homebrewError: String?
    @Published var homebrewSearchQuery = ""
    @Published var homebrewInstalledFilter = ""
    @Published var homebrewPackageFilter: HomebrewPackageListFilter = .all
    @Published var homebrewSearchResults: [HomebrewPackageSearchResult] = HomebrewPackageSearchResult.featured
    @Published var homebrewSelectedPackageDetail: HomebrewPackageDetail?
    @Published var homebrewSelectedFallbackResult: HomebrewPackageSearchResult?
    @Published var homebrewBusyActionID: String?
    @Published var homebrewDoctorIssues: [HomebrewDoctorIssue] = []
    @Published var homebrewDoctorLastOutput: String?
    @Published var homebrewLogs: [OptimizationLog] = []
    @Published var gitHubCLIInventory: GitHubCLIInventory?
    @Published var gitHubCLIBusy = false
    @Published var gitHubCLIError: String?

    @Published var magikaStatus = MagikaStatus(executablePath: nil, version: nil)
    @Published var magikaBusy = false
    @Published var magikaError: String?
    @Published var magikaTargets: [MagikaScanTarget] = []
    @Published var magikaReport: MagikaScanReport?
    @Published var magikaSearchQuery = ""
    @Published var magikaShowInterestingOnly = false
    @Published var magikaRecursiveDirectories = true {
        didSet {
            UserDefaults.standard.set(magikaRecursiveDirectories, forKey: PreferenceKey.magikaRecursiveDirectories)
        }
    }

    @Published var orphanedFiles: [OrphanedFileCandidate] = []
    @Published var orphanedFilesBusy = false
    @Published var orphanedFilesError: String?
    @Published var orphanedFilesProgress: ScanProgress?
    @Published var orphanedFilesSearch = ""

    @Published var startupItems: [StartupItem] = []
    @Published var startupItemsBusy = false
    @Published var startupItemsError: String?
    @Published var startupItemBusyID: String?

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
    private lazy var orphanedFileScanner = OrphanedFileScanner(guardService: guardService, sizer: sizer)
    private lazy var networkInspector = NetworkInspectorService()
    private lazy var processInspector = ProcessInspectorService(guardService: guardService)
    private lazy var quarantineAudit = QuarantineAuditService(guardService: guardService, sizer: sizer)
    private lazy var homebrewService = HomebrewService()
    private lazy var gitHubCLIService = GitHubCLIService()
    private let magikaService = MagikaService()
    private let startupItemsService = StartupItemsService()
    private let optimizer = OptimizationService()
    private let privilegedHelper = PrivilegedHelperManager()
    private let menuBarCompanion = MenuBarCompanionManager()
    private let metricsSampler = SystemMetricsSampler()
    private let companionSettingsStore = MenuBarCompanionSettingsStore()
    private let storageFocusTransformer = StorageFocusTransformer()
    private lazy var exportRegistry = MaintenanceExportRegistry()
    private var notificationObservers: [NSObjectProtocol] = []

    private var hasLoadedCleanup = false
    private var hasLoadedApplications = false
    private var hasLoadedOrphanedFiles = false
    private var hasLoadedStorage = false
    private var hasLoadedNetwork = false
    private var hasLoadedProcesses = false
    private var hasLoadedQuarantine = false
    private var hasLoadedHomebrew = false
    private var hasLoadedGitHubCLI = false
    private var hasLoadedMagika = false
    private var hasLoadedPrivilegedHelper = false
    private var hasLoadedStartupItems = false
    private var hasPreparedInitialSelection = false

    private var cleanupRequestID = UUID()
    private var applicationsRequestID = UUID()
    private var orphanedFilesRequestID = UUID()
    private var storageRequestID = UUID()
    private var networkRequestID = UUID()
    private var processRequestID = UUID()
    private var quarantineRequestID = UUID()
    private var homebrewRequestID = UUID()
    private var homebrewSearchRequestID = UUID()
    private var gitHubCLIRequestID = UUID()
    private var magikaRequestID = UUID()
    private var startupItemsRequestID = UUID()

    private var cleanupTask: Task<[CleanupCategorySummary], Never>?
    private var applicationsTask: Task<[InstalledApp], Never>?
    private var orphanedFilesTask: Task<[OrphanedFileCandidate], Never>?
    private var storageTask: Task<StorageReport, Never>?
    private var networkTask: Task<NetworkInspectorReport, Never>?
    private var processTask: Task<[NativeProcessActivity], Never>?
    private var quarantineTask: Task<[QuarantinedApplication], Never>?
    private var homebrewTask: Task<HomebrewInventory, Never>?
    private var homebrewSearchTask: Task<[HomebrewPackageSearchResult], Never>?
    private var gitHubCLITask: Task<GitHubCLIInventory, Never>?
    private var magikaTask: Task<MagikaScanReport?, Never>?
    private var startupItemsTask: Task<[StartupItem], Never>?
    private var homebrewSelectedReference: HomebrewPackageReference?
    private var scheduledMaintenanceTask: Task<Void, Never>?

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

    var storageFocusConfiguration: StorageFocusConfiguration {
        StorageFocusConfiguration(
            mode: storageFocusMode,
            minimumSize: storageMinimumSize,
            collapseCommonClutter: storageCollapseCommonClutter
        )
    }

    var homebrewStatus: HomebrewStatus {
        homebrewInventory?.status ?? HomebrewStatus(executablePath: nil, version: nil, prefix: nil)
    }

    var filteredHomebrewPackages: [HomebrewInstalledPackage] {
        let query = homebrewInstalledFilter.trimmingCharacters(in: .whitespacesAndNewlines)

        return (homebrewInventory?.installedPackages ?? []).filter { package in
            let matchesFilter: Bool
            switch homebrewPackageFilter {
            case .all:
                matchesFilter = true
            case .formulae:
                matchesFilter = package.kind == .formula
            case .casks:
                matchesFilter = package.kind == .cask
            case .outdated:
                matchesFilter = package.isOutdated
            }

            guard matchesFilter else {
                return false
            }

            guard !query.isEmpty else {
                return true
            }

            return package.displayName.localizedCaseInsensitiveContains(query)
                || package.token.localizedCaseInsensitiveContains(query)
                || package.description.localizedCaseInsensitiveContains(query)
        }
    }

    var homebrewServices: [HomebrewServiceEntry] {
        homebrewInventory?.services ?? []
    }

    var filteredProcessInspectorItems: [NativeProcessActivity] {
        let query = processSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseItems: [NativeProcessActivity]

        switch processSortMode {
        case .cpu:
            baseItems = processInspectorItems.sorted { left, right in
                if abs(left.cpuPercent - right.cpuPercent) > 0.05 {
                    return left.cpuPercent > right.cpuPercent
                }
                return left.memoryBytes > right.memoryBytes
            }
        case .memory:
            baseItems = processInspectorItems.sorted { left, right in
                if left.memoryBytes != right.memoryBytes {
                    return left.memoryBytes > right.memoryBytes
                }
                return left.cpuPercent > right.cpuPercent
            }
        case .name:
            baseItems = processInspectorItems.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }

        guard !query.isEmpty else {
            return baseItems
        }

        return baseItems.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.command.localizedCaseInsensitiveContains(query)
                || "\($0.pid)".contains(query)
        }
    }

    var filteredQuarantinedApplications: [QuarantinedApplication] {
        let query = quarantineSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return quarantinedApplications
        }

        return quarantinedApplications.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
                || $0.url.path.localizedCaseInsensitiveContains(query)
        }
    }

    var filteredMagikaItems: [MagikaScanItem] {
        let query = magikaSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        return (magikaReport?.items ?? []).filter { item in
            if magikaShowInterestingOnly, !item.isInteresting {
                return false
            }

            guard !query.isEmpty else {
                return true
            }

            return item.displayName.localizedCaseInsensitiveContains(query)
                || item.path.path.localizedCaseInsensitiveContains(query)
                || item.group.localizedCaseInsensitiveContains(query)
                || (item.trustedType?.label.localizedCaseInsensitiveContains(query) ?? false)
                || (item.modelType?.label.localizedCaseInsensitiveContains(query) ?? false)
                || item.mimeType.localizedCaseInsensitiveContains(query)
        }
    }

    var recommendedHomebrewPackages: [HomebrewPackageSearchResult] {
        let installedReferences = Set(homebrewInventory?.installedPackages.map(\.reference) ?? [])

        return HomebrewPackageSearchResult.featured.filter { result in
            if installedReferences.contains(result.reference) {
                return false
            }

            guard result.kind == .cask else {
                return true
            }

            if let bundleIdentifier = result.bundleIdentifier,
               NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil {
                return false
            }

            if applications.contains(where: { $0.name.localizedCaseInsensitiveCompare(result.displayName) == .orderedSame }) {
                return false
            }

            return true
        }
    }

    var gitHubCLIStatus: GitHubCLIStatus {
        gitHubCLIInventory?.status ?? GitHubCLIStatus(
            executablePath: nil,
            version: nil,
            authStatusOutput: nil,
            userLogin: nil,
            userName: nil,
            profileURL: nil,
            host: nil
        )
    }

    var gitHubRepositories: [GitHubRepositorySummary] {
        gitHubCLIInventory?.repositories ?? []
    }

    var selectedHomebrewDetail: HomebrewPackageDetail? {
        if let homebrewSelectedPackageDetail {
            return homebrewSelectedPackageDetail
        }

        if let homebrewSelectedFallbackResult {
            return .fallback(from: homebrewSelectedFallbackResult)
        }

        return nil
    }

    var availableExportPlugins: [MaintenanceExportPluginDescriptor] {
        exportRegistry.availablePlugins(for: exportContext())
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

    var filteredOrphanedFiles: [OrphanedFileCandidate] {
        let query = orphanedFilesSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return orphanedFiles }

        return orphanedFiles.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.identifierToken.localizedCaseInsensitiveContains(query)
                || $0.url.path.localizedCaseInsensitiveContains(query)
        }
    }

    var orphanedFileBytes: UInt64 {
        orphanedFiles.reduce(into: 0) { $0 += $1.sizeBytes }
    }

    var startupItemsByKind: [(StartupItemKind, [StartupItem])] {
        StartupItemKind.allCases.compactMap { kind in
            let matches = startupItems.filter { $0.kind == kind }
            guard !matches.isEmpty else {
                return nil
            }

            return (kind, matches)
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
            MaintenanceQuickAction(id: "orphan-review", title: "Orphan Review", subtitle: "Inspect leftover app support files", icon: "questionmark.folder"),
            MaintenanceQuickAction(id: "file-intelligence", title: "File Intelligence", subtitle: "Classify files by content with Magika when available", icon: "doc.text.viewfinder"),
            MaintenanceQuickAction(id: "network-inspector", title: "Network Inspector", subtitle: "Open the on-demand process and connection view", icon: "network"),
            MaintenanceQuickAction(id: "process-inspector", title: "Process Inspector", subtitle: "Review active processes and terminate safe user-owned work", icon: "list.bullet.rectangle.portrait"),
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
        self.menuBarCompanionEnabled = defaults.object(forKey: PreferenceKey.menuBarCompanionEnabled) as? Bool ?? false
        self.showFullDiskAccessReminders = defaults.object(forKey: PreferenceKey.showFullDiskAccessReminders) as? Bool ?? true
        self.hasCompletedOnboarding = defaults.object(forKey: PreferenceKey.hasCompletedOnboarding) as? Bool ?? false
        self.showOnboarding = !self.hasCompletedOnboarding
        self.uninstallSensitivity = defaults.string(forKey: PreferenceKey.uninstallSensitivity).flatMap(UninstallSensitivityLevel.init(rawValue:)) ?? .enhanced
        self.storageInspectionMode = defaults.string(forKey: PreferenceKey.storageInspectionMode).flatMap(StorageInspectionMode.init(rawValue:)) ?? .visible
        self.storageFocusMode = defaults.string(forKey: PreferenceKey.storageFocusMode).flatMap(StorageFocusMode.init(rawValue:)) ?? .balanced
        self.storageMinimumSize = defaults.string(forKey: PreferenceKey.storageMinimumSize).flatMap(StorageMinimumSizeFilter.init(rawValue:)) ?? .all
        self.storageCollapseCommonClutter = defaults.object(forKey: PreferenceKey.storageCollapseClutter) as? Bool ?? true
        self.magikaRecursiveDirectories = defaults.object(forKey: PreferenceKey.magikaRecursiveDirectories) as? Bool ?? true
        self.networkResolveHostnames = defaults.object(forKey: PreferenceKey.networkResolveHostnames) as? Bool ?? false
        self.networkIncludeListeningSockets = defaults.object(forKey: PreferenceKey.networkIncludeListeningSockets) as? Bool ?? true
        self.processSortMode = defaults.string(forKey: PreferenceKey.processSortMode).flatMap(ProcessSortMode.init(rawValue:)) ?? .cpu
        self.scheduledMaintenanceInterval = defaults.string(forKey: PreferenceKey.scheduledMaintenanceInterval).flatMap(ScheduledMaintenanceInterval.init(rawValue:)) ?? .off
        self.scheduledMaintenanceExportFormat = defaults.string(forKey: PreferenceKey.scheduledMaintenanceFormat).flatMap(ScheduledMaintenanceExportFormat.init(rawValue:)) ?? .markdown
        self.lastScheduledMaintenanceRun = defaults.object(forKey: PreferenceKey.scheduledMaintenanceLastRun) as? Date
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

        startScheduledMaintenanceLoop()
    }

    func prepareMainWindow() async {
        SKMoleLog.lifecycle.info("Preparing main window")
        syncMenuBarCompanion(launchIfEnabled: menuBarCompanionEnabled)
        refreshFullDiskAccessStatus()
        await runScheduledMaintenanceIfNeeded(reason: "window-open")
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        showOnboarding = false
        UserDefaults.standard.set(true, forKey: PreferenceKey.hasCompletedOnboarding)
    }

    func dismissOnboardingForNow() {
        showOnboarding = false
    }

    func reopenOnboarding() {
        showOnboarding = true
    }

    func prepareSelection() async {
        let shouldForceRefresh = !hasPreparedInitialSelection && autoRefreshOnOpen
        hasPreparedInitialSelection = true
        SKMoleLog.sidebar.info("Preparing section: \(self.selection.rawValue, privacy: .public)")
        await loadData(for: selection, force: shouldForceRefresh)
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
        SKMoleLog.sidebar.info("Opening section: \(section.rawValue, privacy: .public)")
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

        if networkReport != nil {
            await loadNetwork(force: true)
        }

        if hasLoadedProcesses {
            await loadProcesses(force: true)
        }
    }

    func refreshCleanup() async {
        await loadCleanup(force: true)
    }

    func refreshOrphanedFiles() async {
        if !hasLoadedApplications {
            await loadApplications(force: true)
        }
        await loadOrphanedFiles(force: true)
    }

    func trash(_ candidate: CleanupCandidate) async {
        await trashCleanupCandidates([candidate])
    }

    func trashCleanupCandidates(_ candidates: [CleanupCandidate]) async {
        cleanupBusy = true
        cleanupError = nil

        for candidate in candidates where candidate.safetyLevel != .protected {
            do {
                try await guardService.removePermanently(candidate.url, purpose: .cleanup)
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

    func removeOrphanedFiles(_ candidates: [OrphanedFileCandidate]) async {
        orphanedFilesBusy = true
        orphanedFilesError = nil

        for candidate in candidates {
            do {
                try await guardService.moveToTrash(candidate.url, purpose: .uninstall)
            } catch {
                orphanedFilesError = error.localizedDescription
            }
        }

        await loadOrphanedFiles(force: true)
        if hasLoadedCleanup {
            await loadCleanup(force: true)
        }
        if hasLoadedStorage {
            await loadStorage(force: true)
        }
    }

    func refreshStartupItems() async {
        await loadStartupItems(force: true)
    }

    func disableStartupItem(_ item: StartupItem) async {
        startupItemBusyID = item.id
        startupItemsError = nil

        do {
            let output = try await startupItemsService.disable(item)
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Disable \(item.displayName)",
                    output: output,
                    succeeded: true,
                    timestamp: .now
                ),
                at: 0
            )
            await loadStartupItems(force: true)
        } catch {
            startupItemsError = error.localizedDescription
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Disable \(item.displayName)",
                    output: error.localizedDescription,
                    succeeded: false,
                    timestamp: .now
                ),
                at: 0
            )
        }

        startupItemBusyID = nil
    }

    func enableStartupItem(_ item: StartupItem) async {
        startupItemBusyID = item.id
        startupItemsError = nil

        do {
            let output = try await startupItemsService.enable(item)
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Enable \(item.displayName)",
                    output: output,
                    succeeded: true,
                    timestamp: .now
                ),
                at: 0
            )
            await loadStartupItems(force: true)
        } catch {
            startupItemsError = error.localizedDescription
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Enable \(item.displayName)",
                    output: error.localizedDescription,
                    succeeded: false,
                    timestamp: .now
                ),
                at: 0
            )
        }

        startupItemBusyID = nil
    }

    func refreshQuarantinedApplications() async {
        await loadQuarantinedApplications(force: true)
    }

    func selectQuarantinedApplication(_ app: QuarantinedApplication) {
        selection = .quarantine
        selectedQuarantinedApp = app
    }

    func removeQuarantine(from apps: [QuarantinedApplication]) async {
        let actionableApps = apps.filter { !$0.id.isEmpty }
        guard !actionableApps.isEmpty else {
            return
        }

        quarantineBusyActionID = actionableApps.count == 1 ? actionableApps[0].id : "bulk"
        quarantineError = nil

        let logs = await quarantineAudit.removeQuarantine(from: actionableApps)
        quarantineLogs.insert(contentsOf: logs.reversed(), at: 0)

        if let failedLog = logs.first(where: { !$0.succeeded }) {
            quarantineError = failedLog.output
        } else {
            await loadQuarantinedApplications(force: true)
        }

        quarantineBusyActionID = nil
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
        uninstallPreview = await appInventory.previewSmartDelete(for: app, sensitivity: uninstallSensitivity)
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
        uninstallPreview = await appInventory.previewReset(for: selectedApp, sensitivity: uninstallSensitivity)
        uninstallBusy = false
    }

    func refreshSelectedAppPreviewForSensitivity() async {
        guard let selectedApp else {
            return
        }

        uninstallBusy = true
        uninstallError = nil

        switch uninstallPreview?.mode {
        case .resetApp:
            uninstallPreview = await appInventory.previewReset(for: selectedApp, sensitivity: uninstallSensitivity)
        case .removeLeftoversOnly:
            uninstallPreview = await appInventory.previewSmartDelete(for: selectedApp, sensitivity: uninstallSensitivity)
        case .removeAppAndRemnants, .none:
            uninstallPreview = await defaultPreview(for: selectedApp)
        }

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

    func removeApplications(_ apps: [InstalledApp]) async {
        let uniqueApps = Array(Dictionary(grouping: apps, by: \.id).compactMap(\.value.first))
        guard !uniqueApps.isEmpty else { return }

        uninstallBusy = true
        uninstallError = nil

        var failures: [String] = []

        for app in uniqueApps {
            do {
                let preview = await defaultPreview(for: app)
                try await appInventory.remove(preview)
            } catch {
                failures.append("\(app.name): \(error.localizedDescription)")
            }
        }

        async let refreshApps: Void = loadApplications(force: true)
        async let refreshCleanup: Void = loadCleanup(force: true)
        async let refreshStorage: Void = hasLoadedStorage ? loadStorage(force: true) : ()
        _ = await (refreshApps, refreshCleanup, refreshStorage)

        if failures.isEmpty {
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Bulk App Removal",
                    output: "Removed \(uniqueApps.count) app\(uniqueApps.count == 1 ? "" : "s") using preview-safe uninstall flows.",
                    succeeded: true,
                    timestamp: .now
                ),
                at: 0
            )
        } else {
            uninstallError = failures.joined(separator: "\n")
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Bulk App Removal",
                    output: uninstallError ?? "Bulk removal failed.",
                    succeeded: false,
                    timestamp: .now
                ),
                at: 0
            )
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
                preview = await appInventory.previewReset(for: selectedApp, sensitivity: uninstallSensitivity)
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
            if hasLoadedOrphanedFiles {
                await loadOrphanedFiles(force: true)
            }
            if hasLoadedStartupItems {
                await loadStartupItems(force: true)
            }
            if hasLoadedProcesses {
                await loadProcesses(force: true)
            }
        case "smart-care-report":
            await exportDryRunReport()
        case "orphan-review":
            open(section: .orphans)
            if !hasLoadedApplications {
                await loadApplications(force: true)
            }
            await loadOrphanedFiles(force: true)
        case "file-intelligence":
            open(section: .fileIntelligence)
            await loadMagika(force: false)
        case "network-inspector":
            open(section: .network)
            await loadNetwork(force: true)
        case "process-inspector":
            open(section: .processes)
            await loadProcesses(force: true)
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

    func storageFocusResult(for node: StorageNode) -> StorageFocusResult {
        storageFocusTransformer.transform(node: node, configuration: storageFocusConfiguration)
    }

    func refreshNetwork() async {
        await loadNetwork(force: true)
    }

    func refreshProcesses() async {
        await loadProcesses(force: true)
    }

    func terminateProcess(_ process: NativeProcessActivity) async {
        processTerminationBusyPID = process.pid
        processInspectorError = nil

        do {
            let result = try await processInspector.terminate(process)
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Terminate \(result.processName)",
                    output: result.detail,
                    succeeded: result.succeeded,
                    timestamp: .now
                ),
                at: 0
            )
            await loadProcesses(force: true)
        } catch {
            processInspectorError = error.localizedDescription
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Terminate \(process.name)",
                    output: error.localizedDescription,
                    succeeded: false,
                    timestamp: .now
                ),
                at: 0
            )
        }

        processTerminationBusyPID = nil
    }

    func runScheduledMaintenanceNow() async {
        await performScheduledMaintenance(reason: "manual-run")
    }

    func refreshHomebrew() async {
        await loadHomebrew(force: true)
    }

    func refreshFileIntelligence() async {
        await loadMagika(force: true)
    }

    func pickMagikaTargets() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.prompt = "Add"
        panel.message = "Select files or folders to classify with Magika."

        guard panel.runModal() == .OK else {
            return
        }

        Task { await addMagikaTargets(panel.urls) }
    }

    func addMagikaTargets(_ urls: [URL]) async {
        let validTargets = urls.compactMap(Self.magikaTarget)
        guard !validTargets.isEmpty else {
            magikaError = "Add regular files or folders to inspect with Magika."
            return
        }

        var merged = Dictionary(uniqueKeysWithValues: magikaTargets.map { ($0.id, $0) })
        for target in validTargets {
            merged[target.id] = target
        }

        magikaTargets = merged.values.sorted {
            if $0.kind != $1.kind {
                return $0.kind.rawValue < $1.kind.rawValue
            }

            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        selection = .fileIntelligence
        if !hasLoadedMagika {
            await loadMagika(force: false)
        }

        if magikaStatus.isInstalled {
            await scanSelectedMagikaTargets()
        }
    }

    func removeMagikaTarget(_ target: MagikaScanTarget) {
        magikaTargets.removeAll { $0.id == target.id }

        if magikaTargets.isEmpty {
            magikaReport = nil
            magikaError = nil
        }
    }

    func clearMagikaTargets() {
        magikaTargets.removeAll()
        magikaReport = nil
        magikaError = nil
        magikaSearchQuery = ""
    }

    func scanSelectedMagikaTargets() async {
        guard !magikaTargets.isEmpty else {
            magikaError = "Add at least one file or folder before running Magika."
            return
        }

        await loadMagika(force: true)
    }

    func installMagika() async {
        guard homebrewStatus.isInstalled else {
            selection = .homebrew
            homebrewError = "Install Homebrew first, then SK Mole can install Magika with brew."
            return
        }

        let log = await executeHomebrewCommand(
            arguments: ["install", "magika"],
            actionTitle: "Install Magika",
            actionID: "install:magika"
        )

        if log.succeeded {
            await loadMagika(force: true)
        }
    }

    func openMagikaHomepage() {
        NSWorkspace.shared.open(MagikaStatus.homepageURL)
    }

    func openMagikaRepository() {
        NSWorkspace.shared.open(MagikaStatus.repositoryURL)
    }

    func openMagikaInHomebrew() async {
        let magikaResult = HomebrewPackageSearchResult.featured.first(where: { $0.reference == MagikaStatus.homebrewReference })
            ?? HomebrewPackageSearchResult(
                reference: MagikaStatus.homebrewReference,
                displayName: "Magika",
                description: "AI-powered file content type detection",
                source: "Recommended formula",
                bundleIdentifier: nil
            )

        await selectHomebrewSearchResult(magikaResult)
    }

    func searchHomebrewPackages() async {
        homebrewSearchTask?.cancel()
        let requestID = UUID()
        homebrewSearchRequestID = requestID
        homebrewSearchBusy = true
        homebrewError = nil

        let query = homebrewSearchQuery
        let service = homebrewService
        let task = Task { [requestID] in
            do {
                return try await service.searchPackages(query: query)
            } catch {
                await MainActor.run {
                    guard self.homebrewSearchRequestID == requestID else { return }
                    self.homebrewError = error.localizedDescription
                }

                return HomebrewPackageSearchResult.featured
            }
        }
        homebrewSearchTask = task

        let results = await task.value
        guard homebrewSearchRequestID == requestID else { return }

        homebrewSearchResults = results
        homebrewSearchBusy = false
        homebrewSearchTask = nil
    }

    func selectHomebrewInstalledPackage(_ package: HomebrewInstalledPackage) async {
        selection = .homebrew
        homebrewSelectedPackageDetail = nil
        homebrewSelectedFallbackResult = HomebrewPackageSearchResult(
            reference: package.reference,
            displayName: package.displayName,
            description: package.description,
            source: "Installed package",
            bundleIdentifier: nil
        )
        await loadHomebrewPackageDetail(for: package.reference)
    }

    func selectHomebrewSearchResult(_ result: HomebrewPackageSearchResult) async {
        selection = .homebrew
        homebrewSelectedPackageDetail = nil
        homebrewSelectedFallbackResult = result
        await loadHomebrewPackageDetail(for: result.reference)
    }

    func openHomebrewInstallGuide() {
        NSWorkspace.shared.open(HomebrewStatus.installGuideURL)
    }

    func launchHomebrewInstallerInTerminal() {
        homebrewError = nil
        launchTerminalCommand(HomebrewStatus.installCommand) { [weak self] message in
            self?.homebrewError = message
        }
    }

    func openHomebrewHomepage() {
        guard let url = selectedHomebrewDetail?.homepage else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func refreshGitHubCLI() async {
        await loadGitHubCLI(force: true)
    }

    func installGitHubCLI() async {
        guard homebrewStatus.isInstalled else {
            homebrewError = "Install Homebrew first, then SK Mole can install GitHub CLI with brew."
            return
        }

        let log = await executeHomebrewCommand(
            arguments: ["install", "gh"],
            actionTitle: "Install GitHub CLI",
            actionID: "install:gh-cli"
        )

        if log.succeeded {
            await loadGitHubCLI(force: true)
        }
    }

    func launchGitHubCLILoginInTerminal() {
        gitHubCLIError = nil
        launchTerminalCommand(GitHubCLIStatus.authCommand) { [weak self] message in
            self?.gitHubCLIError = message
        }
    }

    func openGitHubCLIHomepage() {
        NSWorkspace.shared.open(GitHubCLIStatus.homepageURL)
    }

    func openGitHubCLILoginGuide() {
        NSWorkspace.shared.open(GitHubCLIStatus.authGuideURL)
    }

    func openGitHubPersonalAccessTokenPage() {
        NSWorkspace.shared.open(GitHubCLIStatus.personalAccessTokenURL)
    }

    func openGitHubPersonalAccessTokenDocs() {
        NSWorkspace.shared.open(GitHubCLIStatus.personalAccessTokenDocsURL)
    }

    func openGitHubRepository(_ repository: GitHubRepositorySummary) {
        NSWorkspace.shared.open(repository.url)
    }

    func runHomebrewMaintenance(_ action: HomebrewMaintenanceAction) async {
        let log = await executeHomebrewCommand(
            arguments: action.arguments,
            actionTitle: action.title,
            actionID: "maintenance:\(action.id)"
        )

        guard action == .doctor else {
            return
        }

        homebrewDoctorLastOutput = log.output
        homebrewDoctorIssues = HomebrewService.parseDoctorIssues(from: log.output)
    }

    func installSelectedHomebrewPackage() async {
        guard let detail = selectedHomebrewDetail else { return }
        await executeHomebrewCommand(
            arguments: installationArguments(for: detail.reference),
            actionTitle: "Install \(detail.displayName)",
            actionID: "install:\(detail.id)"
        )
    }

    func upgradeSelectedHomebrewPackage() async {
        guard let detail = selectedHomebrewDetail else { return }
        await executeHomebrewCommand(
            arguments: upgradeArguments(for: detail.reference),
            actionTitle: "Upgrade \(detail.displayName)",
            actionID: "upgrade:\(detail.id)"
        )
    }

    func reinstallSelectedHomebrewPackage() async {
        guard let detail = selectedHomebrewDetail else { return }
        await executeHomebrewCommand(
            arguments: reinstallArguments(for: detail.reference),
            actionTitle: "Reinstall \(detail.displayName)",
            actionID: "reinstall:\(detail.id)"
        )
    }

    func uninstallSelectedHomebrewPackage() async {
        guard let detail = selectedHomebrewDetail else { return }
        await executeHomebrewCommand(
            arguments: uninstallArguments(for: detail.reference),
            actionTitle: "Uninstall \(detail.displayName)",
            actionID: "uninstall:\(detail.id)"
        )
    }

    func cleanupSelectedHomebrewPackage() async {
        guard let detail = selectedHomebrewDetail else { return }
        await executeHomebrewCommand(
            arguments: ["cleanup", detail.token],
            actionTitle: "Cleanup \(detail.displayName)",
            actionID: "cleanup:\(detail.id)"
        )
    }

    func runHomebrewServiceAction(_ verb: String, packageToken: String) async {
        await executeHomebrewCommand(
            arguments: ["services", verb, packageToken],
            actionTitle: "brew services \(verb) \(packageToken)",
            actionID: "service:\(verb):\(packageToken)"
        )
    }

    func deleteHomebrewDoctorPath(_ path: HomebrewDoctorIssuePath) async {
        let actionID = "doctor-delete:\(path.id)"
        homebrewBusyActionID = actionID
        homebrewError = nil

        do {
            try await guardService.removePermanently(URL(fileURLWithPath: path.path), purpose: .developerTooling)

            homebrewLogs.insert(
                OptimizationLog(
                    actionTitle: "Delete \(path.fileName)",
                    output: "Removed \(path.path)",
                    succeeded: true,
                    timestamp: .now
                ),
                at: 0
            )

            homebrewDoctorIssues = homebrewDoctorIssues.compactMap { issue in
                let remainingPaths = issue.paths.filter { $0.path != path.path }
                if issue.paths.isEmpty || remainingPaths.isEmpty {
                    return nil
                }

                return HomebrewDoctorIssue(
                    title: issue.title,
                    summary: issue.summary,
                    paths: remainingPaths,
                    supportingLines: issue.supportingLines
                )
            }

            await runHomebrewMaintenance(.doctor)
        } catch {
            homebrewError = error.localizedDescription
            homebrewLogs.insert(
                OptimizationLog(
                    actionTitle: "Delete \(path.fileName)",
                    output: error.localizedDescription,
                    succeeded: false,
                    timestamp: .now
                ),
                at: 0
            )
        }

        homebrewBusyActionID = nil
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
        privilegedHelperBusy = true
        privilegedHelperError = nil
        privilegedHelperState = privilegedHelper.status()
        privilegedHelperReachability = "Checking..."

        guard privilegedHelperState.isEnabled else {
            privilegedHelperReachability = privilegedHelperState.requiresApproval ? "Awaiting approval" : "Unavailable"
            hasLoadedPrivilegedHelper = true
            updateRecommendedActions()
            privilegedHelperBusy = false
            return
        }

        do {
            privilegedHelperReachability = try await privilegedHelper.ping()
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Privileged Helper Status",
                    output: privilegedHelperReachability,
                    succeeded: true,
                    timestamp: .now
                ),
                at: 0
            )
        } catch {
            privilegedHelperReachability = "Unavailable"
            let diagnosticMessage = await helperDiagnosticMessage(for: error)
            privilegedHelperError = diagnosticMessage
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Privileged Helper Status",
                    output: diagnosticMessage,
                    succeeded: false,
                    timestamp: .now
                ),
                at: 0
            )
        }

        hasLoadedPrivilegedHelper = true
        updateRecommendedActions()
        privilegedHelperBusy = false
    }

    func registerPrivilegedHelper() async {
        privilegedHelperBusy = true
        privilegedHelperError = nil

        do {
            if privilegedHelperState.isEnabled, privilegedHelperReachability == "Unavailable" {
                _ = try privilegedHelper.unregister()
                privilegedHelperState = try privilegedHelper.register()
                optimizationLogs.insert(
                    OptimizationLog(
                        actionTitle: "Reinstall Privileged Helper",
                        output: privilegedHelperState.detail,
                        succeeded: true,
                        timestamp: .now
                    ),
                    at: 0
                )
            } else if !privilegedHelperState.isEnabled {
                privilegedHelperState = try privilegedHelper.register()
                optimizationLogs.insert(
                    OptimizationLog(
                        actionTitle: "Register Privileged Helper",
                        output: privilegedHelperState.detail,
                        succeeded: true,
                        timestamp: .now
                    ),
                    at: 0
                )
            }
            await refreshPrivilegedHelperState()
        } catch {
            privilegedHelperError = error.localizedDescription
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Register Privileged Helper",
                    output: error.localizedDescription,
                    succeeded: false,
                    timestamp: .now
                ),
                at: 0
            )
            privilegedHelperBusy = false
        }
    }

    func unregisterPrivilegedHelper() async {
        privilegedHelperBusy = true
        privilegedHelperError = nil

        do {
            privilegedHelperState = try privilegedHelper.unregister()
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Unregister Privileged Helper",
                    output: privilegedHelperState.detail,
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
                    actionTitle: "Unregister Privileged Helper",
                    output: error.localizedDescription,
                    succeeded: false,
                    timestamp: .now
                ),
                at: 0
            )
            privilegedHelperBusy = false
        }
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
        async let refreshProcesses: Void = hasLoadedProcesses ? loadProcesses(force: true) : ()
        _ = await (refreshCleanup, refreshApplications, refreshStorage, refreshProcesses)

        if hasLoadedOrphanedFiles {
            await loadOrphanedFiles(force: true)
        }

        if hasLoadedStartupItems {
            await loadStartupItems(force: true)
        }
    }

    func exportDryRunReport() async {
        await export(using: .dryRunJSON)
    }

    func exportFocusedStorageTree() async {
        await export(using: .focusedStorageJSON)
    }

    func exportFocusedStorageTree(for node: StorageNode) async {
        await export(using: .focusedStorageJSON, storageNodeOverride: storageFocusResult(for: node).node)
    }

    func export(using pluginID: MaintenanceExportPluginID, storageNodeOverride: StorageNode? = nil) async {
        let context = exportContext(storageNodeOverride: storageNodeOverride)

        do {
            let document = try exportRegistry.export(plugin: pluginID, context: context)
            let formatter = ISO8601DateFormatter()
            let timestamp = formatter.string(from: context.maintenanceReport.createdAt).replacingOccurrences(of: ":", with: "-")
            let fileName = "\(document.descriptor.suggestedBaseName)-\(timestamp).\(document.descriptor.fileExtension)"

            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = fileName
            panel.allowedContentTypes = [document.descriptor.contentType]
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")

            guard panel.runModal() == .OK, let destination = panel.url else {
                return
            }

            try document.data.write(to: destination, options: .atomic)
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Export: \(document.descriptor.title)",
                    output: "Saved export to \(destination.path)",
                    succeeded: true,
                    timestamp: .now
                ),
                at: 0
            )
            SKMoleLog.maintenance.info("Saved export \(document.descriptor.title, privacy: .public) to \(destination.path, privacy: .public)")
        } catch {
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Export",
                    output: error.localizedDescription,
                    succeeded: false,
                    timestamp: .now
                ),
                at: 0
            )
            SKMoleLog.maintenance.error("Export failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startScheduledMaintenanceLoop() {
        scheduledMaintenanceTask?.cancel()
        scheduledMaintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(900))
                await self?.runScheduledMaintenanceIfNeeded(reason: "timer")
            }
        }
    }

    private func runScheduledMaintenanceIfNeeded(reason: String) async {
        guard let spacing = scheduledMaintenanceInterval.minimumSpacing else {
            return
        }

        if let lastScheduledMaintenanceRun,
           Date().timeIntervalSince(lastScheduledMaintenanceRun) < spacing {
            return
        }

        await performScheduledMaintenance(reason: reason)
    }

    private func performScheduledMaintenance(reason: String) async {
        SKMoleLog.maintenance.info("Running scheduled maintenance (\(reason, privacy: .public))")

        async let refreshCleanup: Void = loadCleanup(force: true)
        async let refreshApplications: Void = loadApplications(force: true)
        async let refreshStorage: Void = loadStorage(force: true)
        async let refreshProcesses: Void = loadProcesses(force: true)
        _ = await (refreshCleanup, refreshApplications, refreshStorage, refreshProcesses)

        if hasLoadedOrphanedFiles || !orphanedFiles.isEmpty {
            await loadOrphanedFiles(force: true)
        }

        let context = exportContext()

        do {
            let document = try exportRegistry.export(
                plugin: scheduledMaintenanceExportFormat.pluginID,
                context: context
            )
            let destination = try scheduledMaintenanceDestination(for: document.descriptor)
            try document.data.write(to: destination, options: .atomic)
            lastScheduledMaintenanceRun = .now

            let output = "Saved scheduled \(document.descriptor.title) export to \(destination.path)"
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Scheduled Maintenance",
                    output: output,
                    succeeded: true,
                    timestamp: .now
                ),
                at: 0
            )
            SKMoleLog.maintenance.info("\(output, privacy: .public)")
        } catch {
            optimizationLogs.insert(
                OptimizationLog(
                    actionTitle: "Scheduled Maintenance",
                    output: error.localizedDescription,
                    succeeded: false,
                    timestamp: .now
                ),
                at: 0
            )
            SKMoleLog.maintenance.error("Scheduled maintenance failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduledMaintenanceDestination(for descriptor: MaintenanceExportPluginDescriptor) throws -> URL {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/SK Mole Reports", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)

        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: .now).replacingOccurrences(of: ":", with: "-")
        return root.appendingPathComponent("\(descriptor.suggestedBaseName)-\(timestamp).\(descriptor.fileExtension)")
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
        case .openSettings:
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
        case .fileIntelligence:
            await loadMagika(force: force || !hasLoadedMagika)
        case .homebrew:
            let shouldRefreshHomebrew = force || !hasLoadedHomebrew
            let shouldRefreshGitHubCLI = force || !hasLoadedGitHubCLI
            async let refreshHomebrew: Void = loadHomebrew(force: shouldRefreshHomebrew)
            async let refreshGitHubCLI: Void = loadGitHubCLI(force: shouldRefreshGitHubCLI)
            _ = await (refreshHomebrew, refreshGitHubCLI)
        case .network:
            await loadNetwork(force: force || !hasLoadedNetwork)
        case .processes:
            await loadProcesses(force: force || !hasLoadedProcesses)
        case .quarantine:
            await loadQuarantinedApplications(force: force || !hasLoadedQuarantine)
        case .orphans:
            let shouldRefreshApplications = force || !hasLoadedApplications
            let shouldRefreshOrphans = force || !hasLoadedOrphanedFiles
            await loadApplications(force: shouldRefreshApplications)
            await loadOrphanedFiles(force: shouldRefreshOrphans)
        case .smartCare:
            let shouldRefreshCleanup = force || !hasLoadedCleanup
            let shouldRefreshApplications = force || !hasLoadedApplications
            let shouldRefreshStorage = force || !hasLoadedStorage
            let shouldRefreshOrphans = force || !hasLoadedOrphanedFiles
            async let refreshCleanup: Void = loadCleanup(force: shouldRefreshCleanup)
            async let refreshApplications: Void = loadApplications(force: shouldRefreshApplications)
            async let refreshStorage: Void = loadStorage(force: shouldRefreshStorage)
            _ = await (refreshCleanup, refreshApplications, refreshStorage)
            await loadOrphanedFiles(force: shouldRefreshOrphans)
        case .cleanup:
            await loadCleanup(force: force || !hasLoadedCleanup)
        case .uninstall:
            await loadApplications(force: force || !hasLoadedApplications)
        case .storage:
            await loadStorage(force: force || !hasLoadedStorage)
        case .optimize:
            if force || !hasLoadedStartupItems {
                await loadStartupItems(force: true)
            }
            if force || !hasLoadedPrivilegedHelper {
                await refreshPrivilegedHelperState()
            }
        }
    }

    private func loadCleanup(force: Bool) async {
        if !force {
            guard !hasLoadedCleanup else {
                return
            }

            guard cleanupTask == nil else {
                return
            }
        }

        cleanupTask?.cancel()
        let requestID = UUID()
        cleanupRequestID = requestID

        cleanupBusy = true
        cleanupError = nil
        SKMoleLog.scans.info("Starting cleanup scan")
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
        SKMoleLog.scans.info("Finished cleanup scan with \(results.count, privacy: .public) categories")
        cleanupProgress = nil
        cleanupTask = nil
        hasLoadedCleanup = true
        updateRecommendedActions()
    }

    private func loadApplications(force: Bool) async {
        if !force {
            guard !hasLoadedApplications else {
                return
            }

            guard applicationsTask == nil else {
                return
            }
        }

        applicationsTask?.cancel()
        let requestID = UUID()
        applicationsRequestID = requestID

        uninstallBusy = true
        uninstallError = nil
        SKMoleLog.scans.info("Starting application inventory scan")
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
        SKMoleLog.scans.info("Finished application inventory scan with \(discovered.count, privacy: .public) managed apps and \(trashed.count, privacy: .public) trashed apps")
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

    private func loadOrphanedFiles(force: Bool) async {
        if !force {
            guard !hasLoadedOrphanedFiles else {
                return
            }

            guard orphanedFilesTask == nil else {
                return
            }
        }

        orphanedFilesTask?.cancel()
        let requestID = UUID()
        orphanedFilesRequestID = requestID

        orphanedFilesBusy = true
        orphanedFilesError = nil
        SKMoleLog.scans.info("Starting orphan review scan")
        orphanedFilesProgress = ScanProgress(
            title: "Orphan review",
            detail: "Preparing orphan scan",
            completedUnits: 0,
            totalUnits: 1
        )

        let scanner = orphanedFileScanner
        let installedApps = applications
        let task = Task { [requestID] in
            await scanner.scan(installedApps: installedApps) { progress in
                await MainActor.run {
                    guard self.orphanedFilesRequestID == requestID else { return }
                    self.orphanedFilesProgress = progress
                }
            }
        }
        orphanedFilesTask = task

        let discovered = await task.value
        guard orphanedFilesRequestID == requestID else { return }

        orphanedFiles = discovered
        orphanedFilesBusy = false
        SKMoleLog.scans.info("Finished orphan review scan with \(discovered.count, privacy: .public) candidates")
        orphanedFilesProgress = nil
        orphanedFilesTask = nil
        hasLoadedOrphanedFiles = true
        updateRecommendedActions()
    }

    private func loadQuarantinedApplications(force: Bool) async {
        if !force {
            guard !hasLoadedQuarantine else {
                return
            }

            guard quarantineTask == nil else {
                return
            }
        }

        quarantineTask?.cancel()
        let requestID = UUID()
        quarantineRequestID = requestID

        quarantineBusy = true
        quarantineError = nil
        quarantineProgress = ScanProgress(
            title: "Quarantine review",
            detail: "Preparing quarantine scan",
            completedUnits: 0,
            totalUnits: 1
        )

        let audit = quarantineAudit
        let task = Task { [requestID] in
            await audit.discoverQuarantinedApplications { progress in
                await MainActor.run {
                    guard self.quarantineRequestID == requestID else { return }
                    self.quarantineProgress = progress
                }
            }
        }
        quarantineTask = task

        let discovered = await task.value
        guard quarantineRequestID == requestID else { return }

        quarantinedApplications = discovered
        quarantineBusy = false
        quarantineProgress = nil
        quarantineTask = nil
        hasLoadedQuarantine = true

        if let selectedQuarantinedApp {
            if let refreshedSelection = discovered.first(where: { $0.id == selectedQuarantinedApp.id }) {
                self.selectedQuarantinedApp = refreshedSelection
            } else {
                self.selectedQuarantinedApp = nil
            }
        } else {
            selectedQuarantinedApp = discovered.first
        }
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
        if !force {
            guard !hasLoadedStorage else {
                return
            }

            guard storageTask == nil else {
                return
            }
        }

        storageTask?.cancel()
        let requestID = UUID()
        storageRequestID = requestID

        storageBusy = true
        storageError = nil
        SKMoleLog.scans.info("Starting storage scan")
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
        SKMoleLog.scans.info("Finished storage scan across \(report.volumes.count, privacy: .public) visible volumes")
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

    private func loadNetwork(force: Bool) async {
        if !force {
            guard !hasLoadedNetwork else {
                return
            }

            guard networkTask == nil else {
                return
            }
        }

        networkTask?.cancel()
        let requestID = UUID()
        networkRequestID = requestID

        networkBusy = true
        networkError = nil
        SKMoleLog.scans.info("Starting network snapshot")

        let inspector = networkInspector
        let resolveHostnames = networkResolveHostnames
        let includeListening = networkIncludeListeningSockets
        let task = Task { [requestID] in
            do {
                return try await inspector.scan(
                    resolveHostnames: resolveHostnames,
                    includeListening: includeListening
                )
            } catch {
                await MainActor.run {
                    guard self.networkRequestID == requestID else { return }
                    self.networkError = error.localizedDescription
                }

                return NetworkInspectorReport(
                    capturedAt: .now,
                    resolvesHostnames: resolveHostnames,
                    includesListeningSockets: includeListening,
                    interfaces: [],
                    processes: [],
                    connections: [],
                    remoteHosts: []
                )
            }
        }
        networkTask = task

        let report = await task.value
        guard networkRequestID == requestID else { return }

        networkReport = report
        networkBusy = false
        SKMoleLog.scans.info("Finished network snapshot with \(report.processes.count, privacy: .public) processes")
        networkTask = nil
        hasLoadedNetwork = true
        updateRecommendedActions()
    }

    private func loadProcesses(force: Bool) async {
        if !force {
            guard !hasLoadedProcesses else {
                return
            }

            guard processTask == nil else {
                return
            }
        }

        processTask?.cancel()
        let requestID = UUID()
        processRequestID = requestID

        processInspectorBusy = true
        processInspectorError = nil
        SKMoleLog.processes.info("Refreshing process inspector snapshot")

        let inspector = processInspector
        let task = Task {
            await inspector.snapshot()
        }
        processTask = task

        let processes = await task.value
        guard processRequestID == requestID else { return }

        processInspectorItems = processes
        processInspectorBusy = false
        SKMoleLog.processes.info("Loaded \(processes.count, privacy: .public) processes into inspector")
        processTask = nil
        hasLoadedProcesses = true
        updateRecommendedActions()
    }

    private func loadHomebrew(force: Bool) async {
        if !force {
            guard !hasLoadedHomebrew else {
                return
            }

            guard homebrewTask == nil else {
                return
            }
        }

        homebrewTask?.cancel()
        let requestID = UUID()
        homebrewRequestID = requestID

        homebrewBusy = true
        homebrewError = nil

        let service = homebrewService
        let task = Task { [requestID] in
            do {
                return try await service.loadInventory()
            } catch {
                await MainActor.run {
                    guard self.homebrewRequestID == requestID else { return }
                    self.homebrewError = error.localizedDescription
                }

                return HomebrewInventory(
                    status: HomebrewStatus(executablePath: nil, version: nil, prefix: nil),
                    installedPackages: [],
                    services: [],
                    lastUpdated: .now
                )
            }
        }
        homebrewTask = task

        let inventory = await task.value
        guard homebrewRequestID == requestID else { return }

        homebrewInventory = inventory
        homebrewBusy = false
        homebrewTask = nil
        hasLoadedHomebrew = true

        if homebrewSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            homebrewSearchResults = HomebrewPackageSearchResult.featured
        }

        if let reference = homebrewSelectedReference {
            await loadHomebrewPackageDetail(for: reference)
        } else if let firstPackage = inventory.installedPackages.first {
            await selectHomebrewInstalledPackage(firstPackage)
        }
    }

    private func loadGitHubCLI(force: Bool) async {
        if !force {
            guard !hasLoadedGitHubCLI else {
                return
            }

            guard gitHubCLITask == nil else {
                return
            }
        }

        gitHubCLITask?.cancel()
        let requestID = UUID()
        gitHubCLIRequestID = requestID

        gitHubCLIBusy = true
        gitHubCLIError = nil

        let service = gitHubCLIService
        let task = Task { [requestID] in
            do {
                return try await service.loadInventory()
            } catch {
                await MainActor.run {
                    guard self.gitHubCLIRequestID == requestID else { return }
                    self.gitHubCLIError = error.localizedDescription
                }

                return GitHubCLIInventory(
                    status: GitHubCLIStatus(
                        executablePath: nil,
                        version: nil,
                        authStatusOutput: nil,
                        userLogin: nil,
                        userName: nil,
                        profileURL: nil,
                        host: nil
                    ),
                    repositories: [],
                    lastUpdated: .now
                )
            }
        }
        gitHubCLITask = task

        let inventory = await task.value
        guard gitHubCLIRequestID == requestID else { return }

        gitHubCLIInventory = inventory
        gitHubCLIBusy = false
        gitHubCLITask = nil
        hasLoadedGitHubCLI = true
    }

    private func loadMagika(force: Bool) async {
        if !force {
            guard !hasLoadedMagika else {
                return
            }

            guard magikaTask == nil else {
                return
            }
        }

        magikaTask?.cancel()
        let requestID = UUID()
        magikaRequestID = requestID

        magikaBusy = true
        magikaError = nil
        SKMoleLog.scans.info("Refreshing Magika status and file-intelligence results")

        let service = magikaService
        let targets = magikaTargets
        let recursive = magikaRecursiveDirectories
        let task = Task<MagikaScanReport?, Never> { [requestID] in
            do {
                let status = try await service.detectStatus()

                await MainActor.run {
                    guard self.magikaRequestID == requestID else { return }
                    self.magikaStatus = status
                }

                guard status.isInstalled, !targets.isEmpty else {
                    return nil
                }

                return try await service.scan(targets: targets, recursive: recursive, status: status)
            } catch {
                await MainActor.run {
                    guard self.magikaRequestID == requestID else { return }
                    self.magikaError = error.localizedDescription
                }

                return nil
            }
        }
        magikaTask = task

        let report = await task.value
        guard magikaRequestID == requestID else { return }

        if let report {
            magikaReport = report
            SKMoleLog.scans.info("Loaded \(report.scannedCount, privacy: .public) Magika results")
        } else if !magikaStatus.isInstalled {
            magikaReport = nil
        }

        magikaBusy = false
        magikaTask = nil
        hasLoadedMagika = true
    }

    private func loadStartupItems(force: Bool) async {
        if !force {
            guard !hasLoadedStartupItems else {
                return
            }

            guard startupItemsTask == nil else {
                return
            }
        }

        startupItemsTask?.cancel()
        let requestID = UUID()
        startupItemsRequestID = requestID

        startupItemsBusy = true
        startupItemsError = nil

        let service = startupItemsService
        let task = Task { [requestID] in
            do {
                return try await service.loadItems()
            } catch {
                await MainActor.run {
                    guard self.startupItemsRequestID == requestID else { return }
                    self.startupItemsError = error.localizedDescription
                }

                return []
            }
        }
        startupItemsTask = task

        let items = await task.value
        guard startupItemsRequestID == requestID else { return }

        startupItems = items
        startupItemsBusy = false
        startupItemsTask = nil
        hasLoadedStartupItems = true
        updateRecommendedActions()
    }

    private func loadHomebrewPackageDetail(for reference: HomebrewPackageReference) async {
        homebrewSelectedReference = reference
        homebrewDetailBusy = true

        do {
            let detail = try await homebrewService.loadDetail(for: reference)
            guard homebrewSelectedReference == reference else { return }
            homebrewSelectedPackageDetail = detail
            homebrewError = nil
        } catch {
            guard homebrewSelectedReference == reference else { return }
            homebrewSelectedPackageDetail = nil

            if homebrewStatus.isInstalled {
                homebrewError = error.localizedDescription
            }
        }

        homebrewDetailBusy = false
    }

    @discardableResult
    private func executeHomebrewCommand(
        arguments: [String],
        actionTitle: String,
        actionID: String
    ) async -> OptimizationLog {
        homebrewBusyActionID = actionID
        homebrewError = nil

        let log = await homebrewService.run(arguments: arguments, actionTitle: actionTitle)
        homebrewLogs.insert(log, at: 0)

        if log.succeeded {
            await loadHomebrew(force: true)
        } else {
            homebrewError = log.output
        }

        homebrewBusyActionID = nil
        return log
    }

    private func launchTerminalCommand(_ command: String, onError: @escaping (String) -> Void) {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("skmole-terminal", isDirectory: true)
        let scriptURL = tempDirectory.appendingPathComponent("skmole-\(UUID().uuidString).command")
        let script = """
        #!/bin/zsh
        export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
        clear
        echo "SK Mole"
        echo
        \(command)
        status=$?
        echo
        if [ "$status" -eq 0 ]; then
            echo "Command finished successfully."
        else
            echo "Command failed with exit code $status."
        fi
        echo
        echo "Press Return to close this window."
        read -r
        exit "$status"
        """

        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            guard NSWorkspace.shared.open(scriptURL) else {
                onError("SK Mole could not open Terminal for this command. You can run it manually:\n\(command)")
                return
            }
        } catch {
            onError(error.localizedDescription)
        }
    }

    private static func magikaTarget(_ url: URL) -> MagikaScanTarget? {
        let normalized = URLPathSafety.standardized(url)
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory) else {
            return nil
        }

        return MagikaScanTarget(url: normalized, kind: isDirectory.boolValue ? .directory : .file)
    }

    private func installationArguments(for reference: HomebrewPackageReference) -> [String] {
        switch reference.kind {
        case .formula:
            ["install", reference.token]
        case .cask:
            ["install", "--cask", reference.token]
        }
    }

    private func upgradeArguments(for reference: HomebrewPackageReference) -> [String] {
        switch reference.kind {
        case .formula:
            ["upgrade", reference.token]
        case .cask:
            ["upgrade", "--cask", reference.token]
        }
    }

    private func reinstallArguments(for reference: HomebrewPackageReference) -> [String] {
        switch reference.kind {
        case .formula:
            ["reinstall", reference.token]
        case .cask:
            ["reinstall", "--cask", reference.token]
        }
    }

    private func uninstallArguments(for reference: HomebrewPackageReference) -> [String] {
        switch reference.kind {
        case .formula:
            ["uninstall", reference.token]
        case .cask:
            ["uninstall", "--cask", reference.token]
        }
    }

    private func helperDiagnosticMessage(for error: Error) async -> String {
        let helper = privilegedHelper
        let diagnostics = await Task.detached(priority: .utility) {
            helper.diagnosticSummary()
        }.value

        return [error.localizedDescription, diagnostics]
            .compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: "\n")
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
            return await appInventory.previewSmartDelete(for: app, sensitivity: uninstallSensitivity)
        }

        return await appInventory.previewRemoval(for: app, sensitivity: uninstallSensitivity)
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
            storageFocusSummary: storageFocusSummaryLines(),
            networkSummary: networkSummaryLines(),
            processSummary: processSummaryLines(),
            scheduleSummary: scheduledMaintenanceSummaryLines(),
            trashedApps: trashedAppSummary,
            menuBarAlerts: alertSummary
        )
    }

    private func exportContext(storageNodeOverride: StorageNode? = nil) -> MaintenanceExportContext {
        MaintenanceExportContext(
            maintenanceReport: maintenanceReport(),
            focusedStorageNode: storageNodeOverride ?? focusedStorageExportNode(),
            storageFocusConfiguration: storageFocusConfiguration,
            networkReport: networkReport,
            metrics: metrics
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

        if orphanedFileBytes > 0 {
            actions.append(
                RecommendedAction(
                    id: "orphaned-files-review",
                    title: "Review orphaned app leftovers",
                    subtitle: ByteFormatting.format(orphanedFileBytes),
                    detail: "SK Mole found user-domain support files whose owning apps no longer appear installed. Review them before moving them to Trash.",
                    icon: "questionmark.folder",
                    priority: .recommended,
                    estimatedImpactBytes: orphanedFileBytes,
                    callToAction: "Open Orphans",
                    intent: .openSection(.orphans)
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

        let activeStartupItems = startupItems.filter { $0.canToggle && !$0.isDisabled }
        if activeStartupItems.count >= 8 {
            actions.append(
                RecommendedAction(
                    id: "startup-items-review",
                    title: "Review startup items",
                    subtitle: "\(activeStartupItems.count) user launch agents are enabled",
                    detail: "A larger startup set can slow login and keep extra background processes around. SK Mole can review and disable user launch agents one by one.",
                    icon: "person.crop.circle.badge.plus",
                    priority: .optional,
                    callToAction: "Open Optimize",
                    intent: .openSection(.optimize)
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

        if let hottestProcess = metrics.topProcesses.first, hottestProcess.cpuPercent >= 55 {
            actions.append(
                RecommendedAction(
                    id: "process-inspector-\(hottestProcess.pid)",
                    title: "Inspect a hot process",
                    subtitle: "\(hottestProcess.name) • \(String(format: "%.1f%% CPU", hottestProcess.cpuPercent))",
                    detail: "SK Mole is seeing a user-visible CPU spike. Open the process inspector for a wider list and, when safe, terminate non-system work from there.",
                    icon: "list.bullet.rectangle.portrait",
                    priority: .recommended,
                    callToAction: "Open Processes",
                    intent: .openSection(.processes)
                )
            )
        }

        if scheduledMaintenanceInterval == .off {
            actions.append(
                RecommendedAction(
                    id: "scheduled-maintenance-off",
                    title: "Set up scheduled reports",
                    subtitle: "Automatic dry-run exports are still off.",
                    detail: "A daily or weekly report makes it easier to spot storage drift, recurring startup items, and cleanup growth before the Mac feels heavy.",
                    icon: "calendar.badge.clock",
                    priority: .optional,
                    callToAction: "Open Settings",
                    intent: .openSettings
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

    private func storageFocusSummaryLines() -> [String] {
        var lines = [
            "Focus mode: \(storageFocusMode.title)",
            "Minimum size: \(storageMinimumSize.title)",
            "Collapse common clutter: \(storageCollapseCommonClutter ? "On" : "Off")"
        ]

        if let node = focusedStorageExportNode() {
            let result = storageFocusResult(for: node)
            lines.append("Focused node: \(node.name)")
            lines.append("Visible nodes after filters: \(result.visibleChildCount)")
        }

        return lines
    }

    private func networkSummaryLines() -> [String] {
        var lines = [
            "Live throughput: ↓ \(ByteFormatting.formatRate(metrics.networkDownloadRate)) ↑ \(ByteFormatting.formatRate(metrics.networkUploadRate))"
        ]

        if let networkReport {
            lines.append("Processes with sockets: \(networkReport.processes.count)")
            lines.append("Active connections: \(networkReport.activeConnectionCount)")
            lines.append("Remote hosts: \(networkReport.remoteHosts.count)")
            lines.append("Listening sockets included: \(networkReport.includesListeningSockets ? "Yes" : "No")")
        } else {
            lines.append("Network inspector has not been loaded yet.")
        }

        return lines
    }

    private func processSummaryLines() -> [String] {
        var lines = ["Process snapshot count: \(processInspectorItems.count)"]

        if let hottest = processInspectorItems.max(by: { $0.cpuPercent < $1.cpuPercent }) {
            lines.append("Hottest process: \(hottest.name) (\(String(format: "%.1f%% CPU", hottest.cpuPercent)))")
        }

        lines.append("Sort mode: \(processSortMode.title)")
        return lines
    }

    private func scheduledMaintenanceSummaryLines() -> [String] {
        var lines = ["Schedule: \(scheduledMaintenanceInterval.title)"]
        lines.append("Export format: \(scheduledMaintenanceExportFormat.title)")

        if let lastScheduledMaintenanceRun {
            lines.append("Last run: \(ISO8601DateFormatter().string(from: lastScheduledMaintenanceRun))")
        } else {
            lines.append("Last run: none")
        }

        return lines
    }

    private func focusedStorageExportNode() -> StorageNode? {
        if let storageVolumeCurrentNode {
            return storageFocusResult(for: storageVolumeCurrentNode).node
        }

        guard let explorerRoot = storageReport?.explorerRoot else {
            return nil
        }

        return storageFocusResult(for: explorerRoot).node
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
