import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileIntelligenceView: View {
    @ObservedObject var model: AppModel
    @State private var isDropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let magikaError = model.magikaError {
                    errorBanner(magikaError)
                }

                controlsSection
                targetsSection

                if let report = model.magikaReport {
                    summarySection(report)
                    resultsSection(report)
                } else {
                    placeholderSection
                }
            }
            .padding(28)
        }
    }

    private var header: some View {
        SectionCard(
            title: "File Intelligence",
            subtitle: "A Magika-inspired file classification surface that focuses on content, not just extensions. SK Mole uses Magika's trusted output by default and still shows the raw model guess when confidence rules force a safer fallback.",
            symbol: "doc.text.viewfinder"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.magikaStatus.summary)
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text(model.magikaStatus.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let executablePath = model.magikaStatus.executablePath {
                            Text(executablePath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 12) {
                        if let report = model.magikaReport {
                            metricRow(title: "Scanned", value: "\(report.scannedCount)")
                            metricRow(title: "Fallbacks", value: "\(report.confidenceFallbackCount)")
                            metricRow(title: "Mismatches", value: "\(report.extensionMismatchCount)")
                        } else if model.magikaStatus.isInstalled {
                            metricRow(title: "Engine", value: "Magika CLI")
                            metricRow(title: "Mode", value: "Trusted output")
                            metricRow(title: "Folders", value: model.magikaRecursiveDirectories ? "Recursive" : "Direct only")
                        } else {
                            metricRow(title: "Installer", value: "Homebrew / pipx")
                            metricRow(title: "Mode", value: "Optional")
                            metricRow(title: "Output", value: "JSON backed")
                        }
                    }
                }

                HStack(spacing: 12) {
                    if model.magikaStatus.isInstalled {
                        Button("Add Files & Folders") {
                            model.pickMagikaTargets()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Analyze Selection") {
                            Task { await model.scanSelectedMagikaTargets() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.magikaTargets.isEmpty || model.magikaBusy)

                        Button("Refresh Status") {
                            Task { await model.refreshFileIntelligence() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.magikaBusy)
                    } else {
                        if model.homebrewStatus.isInstalled {
                            Button("Install Magika") {
                                Task { await model.installMagika() }
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("Open Homebrew") {
                                model.open(section: .homebrew)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button("Open in Homebrew") {
                            Task { await model.openMagikaInHomebrew() }
                        }
                        .buttonStyle(.bordered)

                        Button("Open Docs") {
                            model.openMagikaHomepage()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Repository") {
                        model.openMagikaRepository()
                    }
                    .buttonStyle(.bordered)

                    if model.magikaBusy {
                        ProgressView()
                    }
                }

                if !model.magikaStatus.isInstalled {
                    MagikaCommandSnippetCard(
                        title: "Preferred install command",
                        command: MagikaStatus.installCommand
                    )
                }
            }
        }
    }

    private var controlsSection: some View {
        SectionCard(
            title: "Scan Controls",
            subtitle: "Keep the workflow light. Add files or folders, decide whether directories should expand recursively, then filter down to the interesting results.",
            symbol: "slider.horizontal.3"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    TextField("Search labels, paths, MIME types, or groups", text: $model.magikaSearchQuery)
                        .textFieldStyle(.roundedBorder)

                    Button("Clear Selection") {
                        model.clearMagikaTargets()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.magikaTargets.isEmpty && model.magikaReport == nil)
                }

                HStack(spacing: 18) {
                    Toggle(
                        "Scan folders recursively",
                        isOn: Binding(
                            get: { model.magikaRecursiveDirectories },
                            set: { model.magikaRecursiveDirectories = $0 }
                        )
                    )
                    .disabled(!model.magikaStatus.isInstalled)

                    Toggle(
                        "Show only interesting findings",
                        isOn: Binding(
                            get: { model.magikaShowInterestingOnly },
                            set: { model.magikaShowInterestingOnly = $0 }
                        )
                    )
                }

                Text("Interesting findings are results where Magika downgraded the raw model guess to a safer output, where the file extension does not match the predicted type, or where the scan itself reported an issue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var targetsSection: some View {
        SectionCard(
            title: "Targets",
            subtitle: "Drop files or folders here, or pick them manually. SK Mole keeps the selection around so you can rerun Magika after changing the recursive setting.",
            symbol: "tray.and.arrow.down"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    targetMetric(title: "Selected", value: "\(model.magikaTargets.count)", detail: "files + folders")
                    targetMetric(title: "Files", value: "\(model.magikaTargets.filter { $0.kind == .file }.count)", detail: "direct paths")
                    targetMetric(title: "Folders", value: "\(model.magikaTargets.filter { $0.kind == .directory }.count)", detail: model.magikaRecursiveDirectories ? "recursive when scanned" : "top-level only")
                }

                dropZone

                if model.magikaTargets.isEmpty {
                    Text("No files or folders selected yet.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(model.magikaTargets) { target in
                            HStack(spacing: 12) {
                                Image(systemName: target.kind.symbol)
                                    .foregroundStyle(AppPalette.accent)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(target.displayName)
                                        .font(.headline)
                                    Text(target.url.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer()

                                Pill(title: target.kind.title, tint: AppPalette.sky)

                                ActionIconButton(symbol: "eye", label: "Reveal \(target.displayName)") {
                                    model.reveal(target.url)
                                }

                                ActionIconButton(symbol: "xmark.circle", label: "Remove \(target.displayName)") {
                                    model.removeMagikaTarget(target)
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
            }
        }
    }

    private func summarySection(_ report: MagikaScanReport) -> some View {
        SectionCard(
            title: "Scan Summary",
            subtitle: "Magika classifies based on content. SK Mole highlights the places where the trusted output differs from the raw model guess, which is often where the scan is most useful.",
            symbol: "chart.bar.doc.horizontal"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 18) {
                    summaryMetric(title: "Visible", value: "\(model.filteredMagikaItems.count)", detail: "results after filters")
                    summaryMetric(title: "Interesting", value: "\(report.interestingCount)", detail: "fallbacks + mismatches + issues")
                    summaryMetric(title: "Fallbacks", value: "\(report.confidenceFallbackCount)", detail: "raw guess overruled")
                    summaryMetric(title: "Bytes", value: ByteFormatting.format(report.totalBytes), detail: "on visible regular files")
                }

                if !report.groupSummaries.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                        ForEach(report.groupSummaries) { summary in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(summary.title)
                                    .font(.headline)
                                Text("\(summary.count) item\(summary.count == 1 ? "" : "s")")
                                    .font(.subheadline.weight(.semibold))
                                Text(ByteFormatting.format(summary.totalBytes))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(AppPalette.secondaryCard.opacity(0.7))
                            )
                        }
                    }
                }

                MagikaCommandSnippetCard(title: "Latest command", command: report.command)
            }
        }
    }

    private func resultsSection(_ report: MagikaScanReport) -> some View {
        SectionCard(
            title: "Results",
            subtitle: report.recursive
                ? "Folder targets were expanded recursively, so this list shows each discovered file."
                : "Folder targets were scanned directly, so rerun with recursion enabled if you want file-by-file results.",
            symbol: "list.bullet.rectangle"
        ) {
            if model.filteredMagikaItems.isEmpty {
                ContentUnavailableView(
                    "No Matching Results",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Try a different search or turn off the interesting-only filter.")
                )
                .frame(minHeight: 260)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(model.filteredMagikaItems.prefix(250)) { item in
                        resultRow(item)
                    }
                }
            }
        }
    }

    private var placeholderSection: some View {
        SectionCard(
            title: "No Scan Yet",
            subtitle: "Add a file or folder, then run Magika to build a content-aware view of what is actually on disk.",
            symbol: "doc.questionmark"
        ) {
            ContentUnavailableView(
                "Nothing Scanned Yet",
                systemImage: "doc.text.viewfinder",
                description: Text("SK Mole keeps Magika optional. Install it only if you want AI-backed file type detection.")
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var dropZone: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "square.and.arrow.down.on.square")
                    .foregroundStyle(isDropTargeted ? AppPalette.accent : .secondary)
                Text("Drop files or folders here to classify them with Magika")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            Text("This is especially useful for unknown downloads, extension mismatches, source trees, and other places where you want content-aware type detection instead of trusting filenames.")
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

    private func resultRow(_ item: MagikaScanItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(item.displayName)
                        .font(.headline)

                    if item.status != "ok" {
                        Pill(title: "Issue", tint: AppPalette.rose)
                    } else {
                        Pill(title: item.group.capitalized, tint: AppPalette.accent)
                    }

                    if let isText = item.isText {
                        Pill(title: isText ? "Text" : "Binary", tint: isText ? AppPalette.sky : AppPalette.amber)
                    }

                    if item.usesConfidenceFallback {
                        Pill(title: "Fallback", tint: AppPalette.amber)
                    }

                    if item.extensionMismatch {
                        Pill(title: "Mismatch", tint: AppPalette.rose)
                    }
                }

                Text(item.path.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let trustedType = item.trustedType {
                    Text(trustedType.description)
                        .font(.subheadline.weight(.semibold))
                    Text("\(trustedType.label) • \(item.mimeType)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let detail = item.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let overwriteSummary = item.overwriteSummary {
                    Text(overwriteSummary)
                        .font(.caption)
                        .foregroundStyle(AppPalette.amber)
                }

                if item.extensionMismatch, let actualExtension = item.actualExtension {
                    Text("Path extension .\(actualExtension) does not match Magika’s common extensions: \(item.expectedExtensions.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(AppPalette.rose)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text(item.confidencePercent)
                    .font(.subheadline.weight(.semibold))
                if let fileSizeBytes = item.fileSizeBytes {
                    Text(ByteFormatting.format(fileSizeBytes))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let modelLabel = item.modelType?.label, modelLabel != item.trustedType?.label {
                    Text("raw: \(modelLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ActionIconButton(symbol: "eye", label: "Reveal \(item.displayName)") {
                model.reveal(item.path)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.7))
        )
    }

    private func targetMetric(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.55))
        )
    }

    private func summaryMetric(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.55))
        )
    }

    private func metricRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppPalette.rose)
            )
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let candidates = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !candidates.isEmpty else {
            return false
        }

        Task {
            var droppedURLs: [URL] = []
            for provider in candidates {
                if let url = await loadDroppedFileURL(from: provider) {
                    droppedURLs.append(url)
                }
            }

            await model.addMagikaTargets(droppedURLs)
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

private struct MagikaCommandSnippetCard: View {
    let title: String
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Copy") {
                    copyToPasteboard(command)
                }
                .buttonStyle(.bordered)
            }

            Text(command)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppPalette.secondaryCard.opacity(0.62))
                )
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
