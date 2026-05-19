import Foundation

@MainActor
final class UpdatesFeatureStore: ObservableObject {
    @Published private(set) var activeAvailableItems: [AppUpdateItem] = []
    @Published private(set) var deferredItems: [AppUpdateItem] = []
    @Published private(set) var ignoredItems: [AppUpdateItem] = []
    @Published private(set) var filteredItems: [AppUpdateItem] = []
    @Published private(set) var filteredAvailableItems: [AppUpdateItem] = []
    @Published private(set) var filteredManualItems: [AppUpdateItem] = []
    @Published private(set) var filteredUnsupportedItems: [AppUpdateItem] = []
    @Published private(set) var filteredUpToDateItems: [AppUpdateItem] = []
    @Published private(set) var filteredDeferredItems: [AppUpdateItem] = []
    @Published private(set) var filteredIgnoredItems: [AppUpdateItem] = []

    func rebuild(
        report: AppUpdateReport?,
        searchQuery: String,
        filter: AppUpdateListFilter,
        ignoredVersions: [String: String],
        deferredExpirations: [String: TimeInterval],
        now: Date = .now
    ) {
        let availableItems = report?.availableItems ?? []
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        deferredItems = availableItems.filter { Self.isDeferred($0, deferredExpirations: deferredExpirations, now: now) }
        ignoredItems = availableItems.filter {
            Self.isIgnored($0, ignoredVersions: ignoredVersions)
                && !Self.isDeferred($0, deferredExpirations: deferredExpirations, now: now)
        }
        activeAvailableItems = availableItems.filter {
            !Self.isIgnored($0, ignoredVersions: ignoredVersions)
                && !Self.isDeferred($0, deferredExpirations: deferredExpirations, now: now)
        }

        let activeIDs = Set(activeAvailableItems.map(\.id))
        let filtered = (report?.items ?? []).filter { item in
            let matchesFilter: Bool
            switch filter {
            case .attention:
                matchesFilter = activeIDs.contains(item.id) || item.status == .manualCheck || item.status == .error
            case .automatic:
                matchesFilter = activeIDs.contains(item.id) && item.canAutoInstall
            case .manual:
                matchesFilter = (activeIDs.contains(item.id) && !item.canAutoInstall)
                    || item.status == .manualCheck
                    || item.status == .error
                    || item.status == .unsupported
            case .all:
                matchesFilter = true
            }

            guard matchesFilter else {
                return false
            }

            return query.isEmpty || item.searchableText.localizedCaseInsensitiveContains(query)
        }

        filteredItems = filtered
        filteredAvailableItems = filtered.filter { activeIDs.contains($0.id) }
        filteredManualItems = filtered.filter { $0.status == .manualCheck || $0.status == .error }
        filteredUnsupportedItems = filtered.filter { $0.status == .unsupported }
        filteredUpToDateItems = filtered.filter { $0.status == .upToDate }
        filteredDeferredItems = Self.filterSuppressedItems(deferredItems, query: query)
        filteredIgnoredItems = Self.filterSuppressedItems(ignoredItems, query: query)
    }

    static func decisionKey(for item: AppUpdateItem) -> String {
        if let bundleIdentifier = item.bundleIdentifier, !bundleIdentifier.isEmpty {
            return "\(item.sourceKind.rawValue):\(bundleIdentifier)"
        }

        if let reference = item.homebrewReference {
            return "\(item.sourceKind.rawValue):\(reference.kind.rawValue):\(reference.token)"
        }

        if let appStoreAdamID = item.appStoreAdamID {
            return "\(item.sourceKind.rawValue):\(appStoreAdamID)"
        }

        return item.id
    }

    static func deferralDate(
        for item: AppUpdateItem,
        deferredExpirations: [String: TimeInterval],
        now: Date = .now
    ) -> Date? {
        guard let rawValue = deferredExpirations[decisionKey(for: item)] else {
            return nil
        }

        let date = Date(timeIntervalSinceReferenceDate: rawValue)
        return date > now ? date : nil
    }

    static func isIgnored(_ item: AppUpdateItem, ignoredVersions: [String: String]) -> Bool {
        guard let ignoredVersion = ignoredVersions[decisionKey(for: item)] else {
            return false
        }

        return ignoredVersion == item.normalizedLatestVersion
    }

    static func isDeferred(
        _ item: AppUpdateItem,
        deferredExpirations: [String: TimeInterval],
        now: Date = .now
    ) -> Bool {
        deferralDate(for: item, deferredExpirations: deferredExpirations, now: now) != nil
    }

    private static func filterSuppressedItems(_ items: [AppUpdateItem], query: String) -> [AppUpdateItem] {
        guard !query.isEmpty else {
            return items
        }

        return items.filter { $0.searchableText.localizedCaseInsensitiveContains(query) }
    }
}
