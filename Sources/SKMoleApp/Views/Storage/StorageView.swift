import SwiftUI

struct StorageView: View {
    @ObservedObject var model: AppModel
    @State private var selectedLargeFileIDs: Set<String> = []
    @State private var explorerPath: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let storageError = model.storageError {
                    Text(storageError)
                        .foregroundStyle(AppPalette.rose)
                        .font(.subheadline)
                }

                if let report = model.storageReport {
                    inspectionModeSection(report)

                    switch model.storageInspectionMode {
                    case .visible:
                        visibleModeSections(report)
                    case .hidden:
                        hiddenModeSections(report)
                    case .admin:
                        adminModeSections(report)
                    }

                    largeFilesSection(report)
                }
            }
            .padding(28)
        }
        .onChange(of: model.storageReport?.largeFiles.map(\.id) ?? []) { _, ids in
            selectedLargeFileIDs = selectedLargeFileIDs.intersection(Set(ids))
        }
        .onChange(of: model.storageReport?.explorerRoot) { _, root in
            explorerPath = sanitizedExplorerPath(in: root)
        }
    }

    private var header: some View {
        SectionCard(
            title: "Storage analysis",
            subtitle: "Switch between visible folders, hidden-space findings, and admin-facing paths, then move from whole-disk review into safe cleanup and uninstall flows.",
            symbol: "internaldrive"
        ) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ByteFormatting.format(model.storageReport?.totalTrackedBytes ?? 0))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("tracked across the current scan")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(model.selectedStorageVolumeRequiresManualScan ? "Scan Selected External Drive" : "Scan Storage", action: scanStorage)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.storageBusy)

                if model.storageBusy {
                    ProgressView()
                }
            }

            if let storageProgress = model.storageProgress {
                InlineScanProgressView(progress: storageProgress, tint: AppPalette.sky)
            } else if model.selectedStorageVolumeRequiresManualScan, let name = model.selectedStorageVolumeDisplayName {
                Text("\(name) is listed, but its folder map will only be built when you run a manual storage scan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func inspectionModeSection(_ report: StorageReport) -> some View {
        SectionCard(
            title: "Inspection mode",
            subtitle: "Use Visible for normal browsing, Hidden for purgeable and snapshot context, or Admin for system-facing storage hotspots.",
            symbol: "slider.horizontal.3"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Picker(
                    "Inspection mode",
                    selection: Binding(
                        get: { model.storageInspectionMode },
                        set: { model.setStorageInspectionMode($0) }
                    )
                ) {
                    ForEach(StorageInspectionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    inspectionModeMetric(
                        title: "Visible",
                        value: "\(report.volumes.count) volumes",
                        detail: ByteFormatting.format(report.totalTrackedBytes)
                    )
                    inspectionModeMetric(
                        title: "Hidden",
                        value: "\(report.hiddenInsights.count) findings",
                        detail: "\(report.hiddenVolumes.count) hidden volumes"
                    )
                    inspectionModeMetric(
                        title: "Admin",
                        value: "\(report.adminInsights.count) findings",
                        detail: model.fullDiskAccessStatus.title
                    )
                }

                Text(model.storageInspectionMode.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func visibleModeSections(_ report: StorageReport) -> some View {
        Group {
            volumeBrowserSection(report.volumes, title: "Volume browser", subtitle: "Browse mounted volumes like a real disk tool, then drill into the heaviest visible folders without leaving the Storage section.")

            StorageExplorerSection(
                currentNode: report.explorerRoot.descendant(for: explorerPath),
                focusResult: model.storageFocusResult(for: report.explorerRoot.descendant(for: explorerPath)),
                breadcrumb: report.explorerRoot.breadcrumb(for: explorerPath),
                onReveal: model.reveal,
                onOpenNode: { node in
                    openExplorerNode(node, within: report.explorerRoot)
                },
                onSelectBreadcrumb: { node in
                    explorerPath = path(for: node.id, in: report.explorerRoot)
                },
                onUseUninstaller: { url in
                    Task { await model.previewDroppedApplication(at: url) }
                },
                onExport: {
                    Task { await model.exportFocusedStorageTree(for: report.explorerRoot.descendant(for: explorerPath)) }
                }
            )

            HStack(alignment: .top, spacing: 22) {
                SectionCard(
                    title: "Usage map",
                    subtitle: "A focused view of the heaviest user-facing categories SK Mole tracks.",
                    symbol: "chart.pie.fill"
                ) {
                    StorageDonutChart(sections: report.sections)
                        .frame(height: 320)
                }
                .frame(maxWidth: 420)

                SectionCard(
                    title: "Category breakdown",
                    subtitle: "The largest tracked roots across apps, home folders, caches, and Trash.",
                    symbol: "chart.bar.doc.horizontal"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(report.sections.prefix(10)) { section in
                            HStack {
                                Label(section.title, systemImage: section.icon)
                                Spacer()
                                Text(ByteFormatting.format(section.sizeBytes))
                                    .font(.headline)
                            }
                        }
                    }
                }
            }
        }
    }

    private func hiddenModeSections(_ report: StorageReport) -> some View {
        Group {
            SectionCard(
                title: "Hidden-space findings",
                subtitle: "Purgeable estimates, local snapshots, and other space macOS can account for without surfacing it cleanly in normal Finder views.",
                symbol: "eye.slash"
            ) {
                if report.hiddenInsights.isEmpty {
                    Text("No hidden-space findings were available from the current scan.")
                        .foregroundStyle(.secondary)
                } else {
                    StorageInsightGrid(insights: report.hiddenInsights, onReveal: model.reveal)
                }
            }

            volumeBrowserSection(
                report.hiddenVolumes,
                title: "Hidden volumes",
                subtitle: "Volumes that are mounted but usually sit outside the normal day-to-day storage view."
            )
        }
    }

    private func adminModeSections(_ report: StorageReport) -> some View {
        SectionCard(
            title: "Admin scan",
            subtitle: "Read-only insight into system-facing storage paths such as VM space, shared caches, backups, and temp folders.",
            symbol: "lock.rectangle.stack"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if model.fullDiskAccessStatus.needsAttention {
                    HStack {
                        Label("Full Disk Access improves this mode", systemImage: "lock.shield")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("Open Privacy & Security") {
                            model.openFullDiskAccessSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppPalette.secondaryCard.opacity(0.7))
                    )
                }

                if report.adminInsights.isEmpty {
                    Text("No admin-facing storage findings were readable in the current scan.")
                        .foregroundStyle(.secondary)
                } else {
                    StorageInsightGrid(insights: report.adminInsights, onReveal: model.reveal)
                }
            }
        }
    }

    private func volumeBrowserSection(_ volumes: [StorageVolume], title: String, subtitle: String) -> some View {
        SectionCard(
            title: title,
            subtitle: subtitle,
            symbol: "externaldrive.connected.to.line.below"
        ) {
            if volumes.isEmpty {
                Text("No mounted volumes were available for browsing.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(volumes) { volume in
                            StorageVolumeTile(
                                volume: volume,
                                isSelected: volume.id == model.selectedStorageVolumeID,
                                action: {
                                    model.focusStorageVolume(volume)
                                }
                            )
                        }
                    }

                    if let storageVolumeError = model.storageVolumeError {
                        Text(storageVolumeError)
                            .foregroundStyle(AppPalette.rose)
                            .font(.subheadline)
                    }

                    if let selectedVolume = volumes.first(where: { $0.id == model.selectedStorageVolumeID }) {
                        StorageVolumeSummary(volume: selectedVolume)

                        if selectedVolume.requiresManualScan {
                            manualScanRequiredCard(for: selectedVolume)
                        } else if let currentNode = model.storageVolumeCurrentNode {
                            let focusResult = model.storageFocusResult(for: currentNode)
                            StorageExplorerBreadcrumbs(
                                nodes: model.storageVolumeBreadcrumb,
                                onSelectNode: model.selectStorageBreadcrumb
                            )

                            storageFocusSection(for: currentNode, focusResult: focusResult)

                            StorageExplorerSummary(
                                currentNode: focusResult.node,
                                onReveal: model.reveal
                            )

                            if model.storageVolumeBusy {
                                ProgressView("Loading deeper folders…")
                            }

                            StorageSpaceMap(
                                currentNode: focusResult.node,
                                onOpen: { node in
                                    Task { await model.drillIntoStorageNode(node) }
                                },
                                onReveal: model.reveal,
                                onUseUninstaller: { url in
                                    Task { await model.previewDroppedApplication(at: url) }
                                }
                            )
                        }
                    } else if let currentNode = model.storageVolumeCurrentNode {
                        let focusResult = model.storageFocusResult(for: currentNode)
                        StorageExplorerBreadcrumbs(
                            nodes: model.storageVolumeBreadcrumb,
                            onSelectNode: model.selectStorageBreadcrumb
                        )

                        storageFocusSection(for: currentNode, focusResult: focusResult)

                        StorageExplorerSummary(
                            currentNode: focusResult.node,
                            onReveal: model.reveal
                        )

                        if model.storageVolumeBusy {
                            ProgressView("Loading deeper folders…")
                        }

                        StorageSpaceMap(
                            currentNode: focusResult.node,
                            onOpen: { node in
                                Task { await model.drillIntoStorageNode(node) }
                            },
                            onReveal: model.reveal,
                            onUseUninstaller: { url in
                                Task { await model.previewDroppedApplication(at: url) }
                            }
                        )
                    }
                }
            }
        }
    }

    private func manualScanRequiredCard(for volume: StorageVolume) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Manual scan required", systemImage: "externaldrive.badge.questionmark")
                .font(.headline)

            Text("SK Mole lists \(volume.name) immediately, but it does not read its folder tree until you explicitly run a storage scan with this volume selected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Scan \(volume.name)") {
                scanStorage()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.storageBusy)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.72))
        )
    }

    private func largeFilesSection(_ report: StorageReport) -> some View {
        SectionCard(
            title: "Large files",
            subtitle: "Oversized files and bundles found during the scan. Select multiple user files to move them to Trash, or route app bundles through Uninstaller.",
            symbol: "arrow.up.right.square"
        ) {
            if report.largeFiles.isEmpty {
                Text("No large files above the current threshold were found.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("\(selectedFiles(in: report).count) selected")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Clear Selection") {
                            selectedLargeFileIDs.removeAll()
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedLargeFileIDs.isEmpty)

                        Button {
                            Task {
                                let files = selectedFiles(in: report)
                                await model.trashStorageFiles(files)
                                selectedLargeFileIDs.removeAll()
                            }
                        } label: {
                            Label("Move Selected to Trash", systemImage: "trash")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedFiles(in: report).isEmpty || model.storageBusy)
                    }

                    ForEach(report.largeFiles) { file in
                        StorageLargeFileRow(
                            file: file,
                            isSelected: selectedLargeFileIDs.contains(file.id),
                            canTrash: model.canTrashFromStorage(file),
                            isBusy: model.storageBusy,
                            onToggleSelection: {
                                toggleSelection(for: file)
                            },
                            onReveal: {
                                model.reveal(file.url)
                            },
                            onTrash: {
                                Task {
                                    await model.trashStorageFile(file)
                                    selectedLargeFileIDs.remove(file.id)
                                }
                            },
                            onUseUninstaller: {
                                Task { await model.previewDroppedApplication(at: file.url) }
                            }
                        )
                    }
                }
            }
        }
    }

    private func scanStorage() {
        Task { await model.refreshStorage() }
    }

    private func toggleSelection(for file: LargeFileEntry) {
        if selectedLargeFileIDs.contains(file.id) {
            selectedLargeFileIDs.remove(file.id)
        } else {
            selectedLargeFileIDs.insert(file.id)
        }
    }

    private func selectedFiles(in report: StorageReport) -> [LargeFileEntry] {
        report.largeFiles.filter { selectedLargeFileIDs.contains($0.id) && model.canTrashFromStorage($0) }
    }

    private func openExplorerNode(_ node: StorageNode, within root: StorageNode) {
        if node.isDrillable {
            explorerPath = path(for: node.id, in: root)
        } else if let url = node.url {
            model.reveal(url)
        }
    }

    private func sanitizedExplorerPath(in root: StorageNode?) -> [String] {
        guard let root else {
            return []
        }

        return root.breadcrumb(for: explorerPath).dropFirst().map(\.id)
    }

    private func path(for targetID: String, in node: StorageNode) -> [String] {
        if node.id == targetID {
            return node.kind == .root ? [] : [node.id]
        }

        for child in node.children {
            let childPath = path(for: targetID, in: child)
            if !childPath.isEmpty {
                return node.kind == .root ? childPath : [node.id] + childPath
            }
        }

        return []
    }

    private func inspectionModeMetric(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.68))
        )
    }

    private func storageFocusSection(for rawNode: StorageNode, focusResult: StorageFocusResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Label("Focus & Filters", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.headline)

                Spacer()

                Button("Export Focused Tree") {
                    Task { await model.exportFocusedStorageTree(for: rawNode) }
                }
                .buttonStyle(.bordered)
            }

            Picker(
                "Focus mode",
                selection: Binding(
                    get: { model.storageFocusMode },
                    set: { model.storageFocusMode = $0 }
                )
            ) {
                ForEach(StorageFocusMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 16) {
                Picker(
                    "Minimum size",
                    selection: Binding(
                        get: { model.storageMinimumSize },
                        set: { model.storageMinimumSize = $0 }
                    )
                ) {
                    ForEach(StorageMinimumSizeFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }

                Toggle(
                    "Collapse common clutter",
                    isOn: Binding(
                        get: { model.storageCollapseCommonClutter },
                        set: { model.storageCollapseCommonClutter = $0 }
                    )
                )
            }

            Text(focusResult.summaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            if focusResult.mode.isSummaryMode {
                Text("File Types is a summary lens. Switch back to Balanced or Folders when you want to drill deeper into actual paths.")
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
}

private struct StorageInsightGrid: View {
    let insights: [StorageInsight]
    let onReveal: (URL) -> Void

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(insights) { insight in
                StorageInsightCard(insight: insight, onReveal: onReveal)
            }
        }
    }
}

private struct StorageInsightCard: View {
    let insight: StorageInsight
    let onReveal: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Label(insight.title, systemImage: insight.icon)
                    .font(.headline)
                    .lineLimit(2)

                Spacer(minLength: 8)

                if insight.requiresAdminContext {
                    Pill(title: "Deep scan", tint: AppPalette.amber)
                }
            }

            Text(ByteFormatting.format(insight.sizeBytes))
                .font(.title3.weight(.bold))

            Text(insight.subtitle)
                .font(.subheadline.weight(.semibold))

            Text(insight.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let url = insight.url {
                ActionIconButton(symbol: "eye", label: "Reveal \(insight.title)") {
                    onReveal(url)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.72))
        )
    }
}

private struct StorageExplorerSection: View {
    let currentNode: StorageNode
    let focusResult: StorageFocusResult
    let breadcrumb: [StorageNode]
    let onReveal: (URL) -> Void
    let onOpenNode: (StorageNode) -> Void
    let onSelectBreadcrumb: (StorageNode) -> Void
    let onUseUninstaller: (URL) -> Void
    let onExport: () -> Void

    var body: some View {
        SectionCard(
            title: "Space map explorer",
            subtitle: "Follow the largest contributors with Dust-style focus modes, collapse rules, and exportable filtered trees.",
            symbol: "square.grid.3x3.square"
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Focus & Filters", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.headline)
                        Text(focusResult.summaryLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Export Focused Tree", action: onExport)
                        .buttonStyle(.bordered)
                }

                StorageExplorerBreadcrumbs(
                    nodes: breadcrumb,
                    onSelectNode: onSelectBreadcrumb
                )

                StorageExplorerSummary(
                    currentNode: focusResult.node,
                    onReveal: onReveal
                )

                StorageSpaceMap(
                    currentNode: focusResult.node,
                    onOpen: onOpenNode,
                    onReveal: onReveal,
                    onUseUninstaller: onUseUninstaller
                )
            }
        }
    }
}

private struct StorageExplorerBreadcrumbs: View {
    let nodes: [StorageNode]
    let onSelectNode: (StorageNode) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(nodes.indices, id: \.self) { index in
                    StorageExplorerBreadcrumbButton(
                        node: nodes[index],
                        isCurrent: index == nodes.count - 1,
                        onSelectNode: onSelectNode
                    )

                    if index < nodes.count - 1 {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct StorageExplorerBreadcrumbButton: View {
    let node: StorageNode
    let isCurrent: Bool
    let onSelectNode: (StorageNode) -> Void

    var body: some View {
        if isCurrent {
            Button(node.name) {
                onSelectNode(node)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(node.name) {
                onSelectNode(node)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct StorageExplorerSummary: View {
    let currentNode: StorageNode
    let onReveal: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                Label(currentNode.name, systemImage: currentNode.icon)
                    .font(.title3.weight(.semibold))
                Spacer()

                if let url = currentNode.url {
                    Button {
                        onReveal(url)
                    } label: {
                        Label("Reveal Current Location", systemImage: "eye")
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 12) {
                explorerMetric(
                    title: "Current total",
                    value: ByteFormatting.format(currentNode.sizeBytes)
                )
                explorerMetric(
                    title: "Visible contributors",
                    value: "\(currentNode.children.count)"
                )
                explorerMetric(
                    title: "Largest child",
                    value: ByteFormatting.format(currentNode.children.first?.sizeBytes ?? 0)
                )
            }

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.7))
        )
    }

    private func explorerMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppPalette.canvas.opacity(0.65))
        )
    }

    private var summary: String {
        if currentNode.children.isEmpty {
            return "This item is already at the end of the current storage drill-down."
        }

        if let largest = currentNode.children.first {
            return "\(largest.name) is the largest visible contributor at this level. Click a lane or a row below to go deeper."
        }

        return "Click a lane or a row below to go deeper into the next level."
    }
}

private struct StorageVolumeTile: View {
    let volume: StorageVolume
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(volume.name, systemImage: volume.kind.symbol)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(volume.requiresManualScan ? volume.scanState.title : volume.kind.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }

                Text(ByteFormatting.format(volume.usedBytes))
                    .font(.title3.weight(.bold))

                Text(volume.requiresManualScan ? volume.scanState.detail : "\(ByteFormatting.format(volume.availableBytes)) free of \(ByteFormatting.format(volume.totalBytes))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.18))

                        Capsule()
                            .fill(Color.white.opacity(0.94))
                            .frame(width: max(proxy.size.width * volume.usageRatio, 10))
                    }
                }
                .frame(height: 10)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? AppPalette.accent : AppPalette.sky.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.4 : 0.1), lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct StorageVolumeSummary: View {
    let volume: StorageVolume

    var body: some View {
        HStack(spacing: 12) {
            summaryBlock(title: "Used", value: ByteFormatting.format(volume.usedBytes))
            summaryBlock(title: "Free", value: ByteFormatting.format(volume.availableBytes))
            summaryBlock(title: "Capacity", value: ByteFormatting.format(volume.totalBytes))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.7))
        )
    }

    private func summaryBlock(title: String, value: String) -> some View {
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
                .fill(AppPalette.canvas.opacity(0.65))
        )
    }
}

private struct StorageLargeFileRow: View {
    let file: LargeFileEntry
    let isSelected: Bool
    let canTrash: Bool
    let isBusy: Bool
    let onToggleSelection: () -> Void
    let onReveal: () -> Void
    let onTrash: () -> Void
    let onUseUninstaller: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if canTrash {
                SelectionCircleButton(
                    isSelected: isSelected,
                    accessibilityLabel: "Select \(file.displayName)",
                    action: onToggleSelection
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(.headline)
                Text("\(ByteFormatting.format(file.sizeBytes)) • \(file.url.deletingLastPathComponent().path)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ActionIconButton(symbol: "eye", label: "Reveal \(file.displayName)", action: onReveal)

            if canTrash {
                ActionIconButton(
                    symbol: "trash",
                    label: "Move \(file.displayName) to Trash",
                    style: .prominent(AppPalette.rose),
                    action: onTrash
                )
                .disabled(isBusy)
            } else if file.isAppBundle {
                ActionIconButton(
                    symbol: "xmark.app",
                    label: "Preview \(file.displayName) in Uninstaller",
                    style: .prominent(AppPalette.accent),
                    action: onUseUninstaller
                )
                .disabled(isBusy)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? AppPalette.accent.opacity(0.16) : AppPalette.secondaryCard.opacity(0.7))
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
