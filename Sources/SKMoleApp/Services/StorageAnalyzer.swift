import Foundation

actor StorageAnalyzer {
    private struct SectionSpec {
        let title: String
        let icon: String
        let urls: [URL]
        let includeHiddenChildren: Bool
    }

    private struct InsightSpec {
        let id: String
        let title: String
        let subtitle: String
        let detail: String
        let icon: String
        let url: URL
        let requiresAdminContext: Bool
    }

    private let guardService: SystemGuard
    private let sizer: DirectorySizer
    private let fileManager = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let maxExplorerDepth = 3
    private let volumeBrowserDepth = 1
    private let drillDownBrowserDepth = 2
    private let maxChildrenPerNode = 8
    private let minimumExplorerNodeSize: UInt64 = 64 * 1_024 * 1_024

    init(guardService: SystemGuard, sizer: DirectorySizer) {
        self.guardService = guardService
        self.sizer = sizer
    }

    func scan(
        manuallyScannedVolumeIDs: Set<String> = [],
        progress: @escaping @Sendable (ScanProgress) async -> Void = { _ in }
    ) async -> StorageReport {
        await sizer.pruneMissingEntries()

        let sections = [
            SectionSpec(title: "Applications", icon: "app.connected.to.app.below.fill", urls: [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")], includeHiddenChildren: false),
            SectionSpec(title: "Downloads", icon: "arrow.down.circle", urls: [home.appendingPathComponent("Downloads")], includeHiddenChildren: false),
            SectionSpec(title: "Desktop", icon: "macwindow", urls: [home.appendingPathComponent("Desktop")], includeHiddenChildren: false),
            SectionSpec(title: "Documents", icon: "doc.text", urls: [home.appendingPathComponent("Documents")], includeHiddenChildren: false),
            SectionSpec(title: "Pictures", icon: "photo.stack", urls: [home.appendingPathComponent("Pictures")], includeHiddenChildren: false),
            SectionSpec(title: "Movies", icon: "film", urls: [home.appendingPathComponent("Movies")], includeHiddenChildren: false),
            SectionSpec(title: "Music", icon: "music.note", urls: [home.appendingPathComponent("Music")], includeHiddenChildren: false),
            SectionSpec(title: "Developer", icon: "hammer.fill", urls: [home.appendingPathComponent("Developer"), home.appendingPathComponent("Library/Developer")], includeHiddenChildren: false),
            SectionSpec(title: "Library caches", icon: "externaldrive.badge.timemachine", urls: [home.appendingPathComponent("Library/Caches")], includeHiddenChildren: false),
            SectionSpec(title: "Trash", icon: "trash", urls: [home.appendingPathComponent(".Trash")], includeHiddenChildren: true)
        ]

        var computedSections: [StorageSection] = []
        var explorerSections: [StorageNode] = []

        for (index, spec) in sections.enumerated() {
            if Task.isCancelled {
                break
            }

            await progress(
                ScanProgress(
                    title: "Storage scan",
                    detail: "Analyzing \(spec.title.lowercased())",
                    completedUnits: index + 1,
                    totalUnits: sections.count + 1
                )
            )

            let existing = spec.urls.filter { self.fileManager.fileExists(atPath: $0.path) }
            var total: UInt64 = 0

            for url in existing {
                if Task.isCancelled {
                    break
                }

                guard await guardService.canOperate(on: url, purpose: .analyze) else {
                    continue
                }
                total += await sizer.size(of: url)
            }

            computedSections.append(
                StorageSection(title: spec.title, icon: spec.icon, sizeBytes: total, urls: existing)
            )

            explorerSections.append(
                await buildSectionNode(
                    spec: spec,
                    urls: existing,
                    sizeBytes: total
                )
            )
        }

        computedSections.sort { $0.sizeBytes > $1.sizeBytes }
        explorerSections = explorerSections
            .filter { $0.sizeBytes > 0 }
            .sorted { $0.sizeBytes > $1.sizeBytes }

        await progress(
            ScanProgress(
                title: "Storage scan",
                detail: "Finding oversized files",
                completedUnits: sections.count + 1,
                totalUnits: sections.count + 1
            )
        )

        let largeFiles = await findLargeFiles(in: computedSections.flatMap(\.urls))
        let volumes = await discoverVolumes(includeHidden: false, manuallyScannedVolumeIDs: manuallyScannedVolumeIDs)
        let hiddenInsights = await discoverHiddenInsights()
        let adminInsights = await discoverAdminInsights()
        let hiddenVolumes = await discoverHiddenVolumes(excluding: volumes, manuallyScannedVolumeIDs: manuallyScannedVolumeIDs)
        let explorerRoot = StorageNode(
            id: "storage-root",
            name: "All Tracked Storage",
            icon: "internaldrive",
            url: nil,
            sizeBytes: computedSections.reduce(into: 0) { $0 += $1.sizeBytes },
            kind: .root,
            children: explorerSections
        )

        return StorageReport(
            sections: computedSections,
            largeFiles: largeFiles,
            explorerRoot: explorerRoot,
            volumes: volumes,
            hiddenInsights: hiddenInsights,
            adminInsights: adminInsights,
            hiddenVolumes: hiddenVolumes
        )
    }

    func browseNode(
        at url: URL,
        displayName: String? = nil,
        knownSize: UInt64? = nil,
        icon: String? = nil,
        kindHint: StorageNodeKind? = nil
    ) async -> StorageNode {
        let normalized = URLPathSafety.standardized(url)
        let values = try? normalized.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .localizedNameKey])
        let isDirectory = values?.isDirectory == true
        let isPackage = values?.isPackage == true || normalized.pathExtension.lowercased() == "app"
        let kind = kindHint ?? (isPackage ? .package : (isDirectory ? .directory : .file))

        let sizeBytes: UInt64
        if let knownSize {
            sizeBytes = knownSize
        } else if kind == .volume {
            sizeBytes = volumeUsedBytes(for: normalized)
        } else {
            sizeBytes = await sizer.size(of: normalized)
        }

        let childNodes: [StorageNode]
        if (kind == .directory || kind == .volume), !isPackage {
            childNodes = await buildNodes(
                for: [normalized],
                parentID: normalized.path,
                parentSize: sizeBytes,
                depth: 0,
                maximumDepth: drillDownBrowserDepth,
                includeHidden: false
            )
        } else {
            childNodes = []
        }

        return StorageNode(
            id: normalized.path,
            name: displayName ?? values?.localizedName ?? normalized.lastPathComponent,
            icon: icon ?? self.icon(for: normalized, kind: kind),
            url: normalized,
            sizeBytes: sizeBytes,
            kind: kind,
            children: childNodes
        )
    }

    private func buildSectionNode(spec: SectionSpec, urls: [URL], sizeBytes: UInt64) async -> StorageNode {
        let sectionID = "section:\(spec.title)"
        let children = await buildNodes(
            for: urls,
            parentID: sectionID,
            parentSize: sizeBytes,
            depth: 0,
            maximumDepth: maxExplorerDepth,
            includeHidden: spec.includeHiddenChildren
        )

        return StorageNode(
            id: sectionID,
            name: spec.title,
            icon: spec.icon,
            url: urls.count == 1 ? urls.first : nil,
            sizeBytes: sizeBytes,
            kind: .section,
            children: children
        )
    }

    private func buildNodes(
        for roots: [URL],
        parentID: String,
        parentSize: UInt64,
        depth: Int,
        maximumDepth: Int,
        includeHidden: Bool
    ) async -> [StorageNode] {
        guard depth < maximumDepth, !roots.isEmpty else {
            return []
        }

        var children: [StorageNode] = []

        for root in roots {
            if Task.isCancelled {
                return children
            }

            guard fileManager.fileExists(atPath: root.path) else {
                continue
            }

            let directChildren = await sizer.children(of: root, includeHidden: includeHidden)

            for child in directChildren {
                if Task.isCancelled {
                    return children
                }

                guard await guardService.canOperate(on: child, purpose: .analyze) else {
                    continue
                }

                let size = await sizer.size(of: child)
                guard size > 0 else {
                    continue
                }

                let values = try? child.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isPackageKey,
                    .localizedNameKey
                ])
                let isDirectory = values?.isDirectory == true
                let isPackage = values?.isPackage == true || child.pathExtension.lowercased() == "app"
                let kind: StorageNodeKind = isPackage ? .package : (isDirectory ? .directory : .file)
                let nodeID = URLPathSafety.standardized(child).path
                let childNodes: [StorageNode]

                if isDirectory, !isPackage {
                    childNodes = await buildNodes(
                        for: [child],
                        parentID: nodeID,
                        parentSize: size,
                        depth: depth + 1,
                        maximumDepth: maximumDepth,
                        includeHidden: includeHidden
                    )
                } else {
                    childNodes = []
                }

                children.append(
                    StorageNode(
                        id: nodeID,
                        name: values?.localizedName ?? child.lastPathComponent,
                        icon: icon(for: child, kind: kind),
                        url: child,
                        sizeBytes: size,
                        kind: kind,
                        children: childNodes
                    )
                )
            }
        }

        return condensedNodes(children, parentID: parentID, parentSize: parentSize, depth: depth)
    }

    private func condensedNodes(
        _ nodes: [StorageNode],
        parentID: String,
        parentSize: UInt64,
        depth: Int
    ) -> [StorageNode] {
        guard !nodes.isEmpty else {
            return []
        }

        let sorted = nodes.sorted { $0.sizeBytes > $1.sizeBytes }
        let dynamicThreshold = max(parentSize / 45, minimumExplorerNodeSize)

        var visible = sorted.filter { $0.sizeBytes >= dynamicThreshold }
        if visible.isEmpty {
            visible = Array(sorted.prefix(maxChildrenPerNode))
        } else {
            visible = Array(visible.prefix(maxChildrenPerNode))
        }

        let totalVisible = visible.reduce(into: 0) { $0 += $1.sizeBytes }
        let totalMeasured = max(parentSize, sorted.reduce(into: 0) { $0 += $1.sizeBytes })
        let remainder = totalMeasured > totalVisible ? totalMeasured - totalVisible : 0

        guard remainder >= minimumExplorerNodeSize / 2 else {
            return visible
        }

        var withRemainder = visible
        withRemainder.append(
            StorageNode(
                id: "\(parentID)#other-\(depth)",
                name: "Other",
                icon: "square.grid.3x1.folder.badge.plus",
                url: nil,
                sizeBytes: remainder,
                kind: .remainder,
                children: []
            )
        )
        return withRemainder
    }

    private func icon(for url: URL, kind: StorageNodeKind) -> String {
        let name = url.lastPathComponent.lowercased()

        switch kind {
        case .root:
            return "internaldrive"
        case .volume:
            return "internaldrive"
        case .section:
            return "square.grid.3x3.square"
        case .directory:
            switch name {
            case "applications":
                return "app.connected.to.app.below.fill"
            case "downloads":
                return "arrow.down.circle"
            case "desktop":
                return "macwindow"
            case "documents":
                return "doc.text"
            case "pictures", "photos library.photoslibrary":
                return "photo.stack"
            case "movies":
                return "film"
            case "music":
                return "music.note"
            case "developer":
                return "hammer.fill"
            case ".trash":
                return "trash"
            case "caches":
                return "externaldrive.badge.timemachine"
            default:
                return "folder.fill"
            }
        case .package:
            return url.pathExtension.lowercased() == "app" ? "app.fill" : "shippingbox.fill"
        case .file:
            switch url.pathExtension.lowercased() {
            case "dmg", "pkg", "xip":
                return "shippingbox.fill"
            case "zip", "rar", "tar", "gz":
                return "archivebox.fill"
            case "mov", "mp4", "mkv":
                return "film.fill"
            case "jpg", "jpeg", "png", "heic":
                return "photo.fill"
            case "mp3", "m4a", "wav":
                return "music.note"
            default:
                return "doc.fill"
            }
        case .remainder:
            return "square.grid.3x1.folder.badge.plus"
        }
    }

    private func discoverVolumes(includeHidden: Bool, manuallyScannedVolumeIDs: Set<String>) async -> [StorageVolume] {
        let keys: [URLResourceKey] = [
            .localizedNameKey,
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityForOpportunisticUsageKey,
            .volumeAvailableCapacityKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey,
            .volumeIsReadOnlyKey,
            .volumeIsRemovableKey
        ]

        let mounted = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: includeHidden ? [] : [.skipHiddenVolumes]
        ) ?? []

        var volumes: [StorageVolume] = []

        for url in mounted.map(URLPathSafety.standardized) {
            if Task.isCancelled {
                return volumes
            }

            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }

            let values = try? url.resourceValues(forKeys: Set(keys))
            let totalBytes = UInt64(values?.volumeTotalCapacity ?? 0)
            let availableValue = values?.volumeAvailableCapacityForImportantUsage ?? Int64(values?.volumeAvailableCapacity ?? 0)
            let availableBytes = availableValue > 0 ? UInt64(availableValue) : 0
            guard totalBytes > 0 else {
                continue
            }

            let kind = volumeKind(for: url, values: values)
            let usedBytes = totalBytes > availableBytes ? totalBytes - availableBytes : 0
            let shouldScanContents = shouldScanContents(for: kind, url: url, manuallyScannedVolumeIDs: manuallyScannedVolumeIDs)
            let rootNode: StorageNode

            if shouldScanContents {
                rootNode = await buildVolumeNode(
                    url: url,
                    displayName: values?.volumeName ?? values?.localizedName ?? url.lastPathComponent,
                    icon: kind.symbol,
                    usedBytes: usedBytes
                )
            } else {
                rootNode = StorageNode(
                    id: url.path,
                    name: values?.volumeName ?? values?.localizedName ?? url.lastPathComponent,
                    icon: kind.symbol,
                    url: url,
                    sizeBytes: usedBytes,
                    kind: .volume,
                    children: []
                )
            }

            volumes.append(
                StorageVolume(
                    name: values?.volumeName ?? values?.localizedName ?? url.lastPathComponent,
                    url: url,
                    totalBytes: totalBytes,
                    availableBytes: availableBytes,
                    kind: kind,
                    scanState: shouldScanContents ? .scanned : .manualRequired,
                    browserRoot: rootNode
                )
            )
        }

        return volumes.sorted { left, right in
            if left.kind == .startup, right.kind != .startup {
                return true
            }

            if left.kind != .startup, right.kind == .startup {
                return false
            }

            if left.usedBytes != right.usedBytes {
                return left.usedBytes > right.usedBytes
            }

            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    private func discoverHiddenInsights() async -> [StorageInsight] {
        let root = URL(fileURLWithPath: "/")
        let values = try? root.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityForOpportunisticUsageKey,
            .volumeAvailableCapacityKey
        ])
        let important = UInt64(max(values?.volumeAvailableCapacityForImportantUsage ?? 0, 0))
        let opportunistic = UInt64(max(values?.volumeAvailableCapacityForOpportunisticUsage ?? Int64(values?.volumeAvailableCapacity ?? 0), 0))
        let purgeableEstimate = opportunistic > important ? opportunistic - important : 0

        var insights: [StorageInsight] = []

        if purgeableEstimate > 0 {
            insights.append(
                StorageInsight(
                    id: "purgeable-estimate",
                    title: "Purgeable estimate",
                    subtitle: "macOS can likely reclaim part of this space on demand",
                    detail: "This is inferred from the gap between opportunistic and important available capacity on the startup volume.",
                    icon: "internaldrive.badge.minus",
                    sizeBytes: purgeableEstimate,
                    url: URL(fileURLWithPath: "/"),
                    requiresAdminContext: false
                )
            )
        }

        let snapshotRoot = URL(fileURLWithPath: "/System/Volumes/Data/.MobileBackups")
        if fileManager.fileExists(atPath: snapshotRoot.path),
           await guardService.canOperate(on: snapshotRoot, purpose: .analyze) {
            let size = await sizer.size(of: snapshotRoot)
            if size > 0 {
                insights.append(
                    StorageInsight(
                        id: "local-snapshots",
                        title: "Local snapshots",
                        subtitle: "Time Machine or APFS snapshots hidden from normal folder views",
                        detail: "These snapshots help restore recent state but can consume hidden disk space.",
                        icon: "clock.arrow.circlepath",
                        sizeBytes: size,
                        url: snapshotRoot,
                        requiresAdminContext: false
                    )
                )
            }
        }

        return insights.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private func discoverAdminInsights() async -> [StorageInsight] {
        let specs = [
            InsightSpec(
                id: "vm-swap",
                title: "VM and swap",
                subtitle: "Sleep images and swap files used for memory pressure",
                detail: "Large here usually means the Mac has been under memory pressure or has hibernation data on disk.",
                icon: "memorychip",
                url: URL(fileURLWithPath: "/private/var/vm"),
                requiresAdminContext: true
            ),
            InsightSpec(
                id: "system-caches",
                title: "System caches",
                subtitle: "Shared caches outside the user Library",
                detail: "These are not deleted by SK Mole, but they help explain system-heavy disk usage.",
                icon: "externaldrive.badge.timemachine",
                url: URL(fileURLWithPath: "/Library/Caches"),
                requiresAdminContext: true
            ),
            InsightSpec(
                id: "system-logs",
                title: "System logs",
                subtitle: "Machine-wide logs and diagnostics",
                detail: "Useful for troubleshooting, but they can also explain a chunk of system data.",
                icon: "doc.text.magnifyingglass",
                url: URL(fileURLWithPath: "/Library/Logs"),
                requiresAdminContext: true
            ),
            InsightSpec(
                id: "ios-backups",
                title: "iPhone and iPad backups",
                subtitle: "Finder backups stored outside normal user folders",
                detail: "These backups can be surprisingly large and are easy to forget about.",
                icon: "iphone.gen3",
                url: home.appendingPathComponent("Library/Application Support/MobileSync/Backup"),
                requiresAdminContext: false
            ),
            InsightSpec(
                id: "system-temp",
                title: "System temp folders",
                subtitle: "Hidden temporary files and caches in /private/var/folders",
                detail: "This area often explains hidden cache growth across multiple apps and services.",
                icon: "folder.badge.gearshape",
                url: URL(fileURLWithPath: "/private/var/folders"),
                requiresAdminContext: true
            )
        ]

        var insights: [StorageInsight] = []
        for spec in specs where fileManager.fileExists(atPath: spec.url.path) {
            if Task.isCancelled {
                break
            }

            guard await guardService.canOperate(on: spec.url, purpose: .analyze) else {
                continue
            }

            let size = await sizer.size(of: spec.url)
            guard size > 0 else {
                continue
            }

            insights.append(
                StorageInsight(
                    id: spec.id,
                    title: spec.title,
                    subtitle: spec.subtitle,
                    detail: spec.detail,
                    icon: spec.icon,
                    sizeBytes: size,
                    url: spec.url,
                    requiresAdminContext: spec.requiresAdminContext
                )
            )
        }

        return insights.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private func discoverHiddenVolumes(excluding visibleVolumes: [StorageVolume], manuallyScannedVolumeIDs: Set<String>) async -> [StorageVolume] {
        let visiblePaths = Set(visibleVolumes.map(\.id))
        return await discoverVolumes(includeHidden: true, manuallyScannedVolumeIDs: manuallyScannedVolumeIDs)
            .filter { !visiblePaths.contains($0.id) }
            .sorted { $0.usedBytes > $1.usedBytes }
    }

    private func buildVolumeNode(
        url: URL,
        displayName: String,
        icon: String,
        usedBytes: UInt64
    ) async -> StorageNode {
        let children = await buildNodes(
            for: [url],
            parentID: url.path,
            parentSize: usedBytes,
            depth: 0,
            maximumDepth: volumeBrowserDepth,
            includeHidden: false
        )

        return StorageNode(
            id: url.path,
            name: displayName,
            icon: icon,
            url: url,
            sizeBytes: usedBytes,
            kind: .volume,
            children: children
        )
    }

    private func volumeKind(for url: URL, values: URLResourceValues?) -> StorageVolumeKind {
        if url.path == "/" {
            return .startup
        }

        if values?.volumeIsReadOnly == true {
            return .readOnly
        }

        if values?.volumeIsLocal == false {
            return .networkDrive
        }

        if values?.volumeIsRemovable == true {
            return .externalDrive
        }

        if values?.volumeIsInternal == true {
            return .internalDrive
        }

        return .externalDrive
    }

    private func shouldScanContents(
        for kind: StorageVolumeKind,
        url: URL,
        manuallyScannedVolumeIDs: Set<String>
    ) -> Bool {
        if manuallyScannedVolumeIDs.contains(url.path) {
            return true
        }

        switch kind {
        case .startup, .internalDrive:
            return true
        case .externalDrive, .networkDrive, .readOnly:
            return false
        }
    }

    private func volumeUsedBytes(for url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        let values = try? url.resourceValues(forKeys: keys)
        let total = UInt64(values?.volumeTotalCapacity ?? 0)
        let preferredAvailable = values?.volumeAvailableCapacityForImportantUsage ?? Int64(values?.volumeAvailableCapacity ?? 0)
        let available = preferredAvailable > 0 ? UInt64(preferredAvailable) : 0
        return total > available ? total - available : 0
    }

    private func findLargeFiles(in roots: [URL]) async -> [LargeFileEntry] {
        let minimumSize: UInt64 = 512 * 1_024 * 1_024
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]

        var matches: [LargeFileEntry] = []

        for root in roots {
            if Task.isCancelled {
                return matches
            }

            guard await guardService.canOperate(on: root, purpose: .analyze) else {
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else {
                continue
            }

            let urls = enumerator.compactMap { $0 as? URL }

            for url in urls {
                if Task.isCancelled {
                    return matches
                }

                guard let values = try? url.resourceValues(forKeys: keys) else {
                    continue
                }

                if values.isDirectory == true, values.isPackage != true {
                    continue
                }

                let size: UInt64
                if values.isPackage == true {
                    size = await sizer.size(of: url)
                    enumerator.skipDescendants()
                } else {
                    size = UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
                }

                guard size >= minimumSize else {
                    continue
                }

                matches.append(
                    LargeFileEntry(
                        url: url,
                        displayName: url.lastPathComponent,
                        sizeBytes: size,
                        modifiedAt: values.contentModificationDate
                    )
                )
            }
        }

        return matches
            .sorted { $0.sizeBytes > $1.sizeBytes }
            .prefix(18)
            .map { $0 }
    }
}
