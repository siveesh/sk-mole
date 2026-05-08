import SwiftUI

struct OrphanedFilesView: View {
    @ObservedObject var model: AppModel
    @State private var selectedIDs: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let orphanedFilesError = model.orphanedFilesError {
                    errorBanner(orphanedFilesError)
                }

                ForEach(groupedCandidates, id: \.0) { category, candidates in
                    OrphanedFileCategoryCard(
                        category: category,
                        candidates: candidates,
                        selectedIDs: selectedIDs,
                        isBusy: model.orphanedFilesBusy,
                        onReveal: model.reveal,
                        onToggleSelection: toggleSelection,
                        onClearSelection: {
                            clearSelection(in: candidates)
                        },
                        onTrashCandidate: { candidate in
                            Task {
                                await model.removeOrphanedFiles([candidate])
                                selectedIDs.remove(candidate.id)
                            }
                        },
                        onTrashSelected: {
                            Task {
                                let selected = candidates.filter { selectedIDs.contains($0.id) }
                                await model.removeOrphanedFiles(selected)
                                clearSelection(in: candidates)
                            }
                        }
                    )
                }
            }
            .padding(28)
        }
        .onChange(of: model.orphanedFiles.map(\.id)) { _, ids in
            selectedIDs = selectedIDs.intersection(Set(ids))
        }
    }

    private var header: some View {
        SectionCard(
            title: "Orphaned files review",
            subtitle: "Find user-domain support files, containers, and launch agents whose owning apps no longer appear installed.",
            symbol: "questionmark.folder"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    TextField("Search orphaned files", text: $model.orphanedFilesSearch)
                        .textFieldStyle(.roundedBorder)

                    Button("Scan Again") {
                        Task { await model.refreshOrphanedFiles() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.orphanedFilesBusy)

                    if model.orphanedFilesBusy {
                        ProgressView()
                    }
                }

                HStack(spacing: 18) {
                    metricBlock(ByteFormatting.format(model.orphanedFileBytes), subtitle: "reclaimable review set")
                    metricBlock("\(model.orphanedFiles.count)", subtitle: "leftover candidates")
                    Spacer()
                }

                if let orphanedFilesProgress = model.orphanedFilesProgress {
                    InlineScanProgressView(progress: orphanedFilesProgress, tint: AppPalette.amber)
                }
            }
        }
    }

    private var groupedCandidates: [(OrphanedFileCategory, [OrphanedFileCandidate])] {
        OrphanedFileCategory.allCases.compactMap { category in
            let matches = model.filteredOrphanedFiles.filter { $0.category == category }
            guard !matches.isEmpty else {
                return nil
            }

            return (category, matches)
        }
    }

    private func metricBlock(_ value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func toggleSelection(_ candidate: OrphanedFileCandidate) {
        if selectedIDs.contains(candidate.id) {
            selectedIDs.remove(candidate.id)
        } else {
            selectedIDs.insert(candidate.id)
        }
    }

    private func clearSelection(in candidates: [OrphanedFileCandidate]) {
        selectedIDs.subtract(candidates.map(\.id))
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
}

private struct OrphanedFileCategoryCard: View {
    let category: OrphanedFileCategory
    let candidates: [OrphanedFileCandidate]
    let selectedIDs: Set<String>
    let isBusy: Bool
    let onReveal: (URL) -> Void
    let onToggleSelection: (OrphanedFileCandidate) -> Void
    let onClearSelection: () -> Void
    let onTrashCandidate: (OrphanedFileCandidate) -> Void
    let onTrashSelected: () -> Void

    var body: some View {
        SectionCard(
            title: category.title,
            subtitle: category.subtitle,
            symbol: category.symbol
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(ByteFormatting.format(totalBytes))
                        .font(.headline)

                    Spacer()

                    Text("\(selectedCount) selected")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Button("Clear Selection", action: onClearSelection)
                        .buttonStyle(.bordered)
                        .disabled(selectedCount == 0)

                    Button(action: onTrashSelected) {
                        Label("Move Selected to Trash", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCount == 0 || isBusy)
                }

                ForEach(candidates) { candidate in
                    OrphanedFileRow(
                        candidate: candidate,
                        isSelected: selectedIDs.contains(candidate.id),
                        isBusy: isBusy,
                        onReveal: {
                            onReveal(candidate.url)
                        },
                        onToggleSelection: {
                            onToggleSelection(candidate)
                        },
                        onTrash: {
                            onTrashCandidate(candidate)
                        }
                    )
                }
            }
        }
    }

    private var selectedCount: Int {
        candidates.filter { selectedIDs.contains($0.id) }.count
    }

    private var totalBytes: UInt64 {
        candidates.reduce(into: 0) { $0 += $1.sizeBytes }
    }
}

private struct OrphanedFileRow: View {
    let candidate: OrphanedFileCandidate
    let isSelected: Bool
    let isBusy: Bool
    let onReveal: () -> Void
    let onToggleSelection: () -> Void
    let onTrash: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            SelectionCircleButton(
                isSelected: isSelected,
                accessibilityLabel: "Select \(candidate.displayName)",
                action: onToggleSelection
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.displayName)
                    .font(.headline)
                Text("\(ByteFormatting.format(candidate.sizeBytes)) • \(candidate.rationale)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(candidate.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            ActionIconButton(symbol: "eye", label: "Reveal \(candidate.displayName)", action: onReveal)
            ActionIconButton(
                symbol: "trash",
                label: "Move \(candidate.displayName) to Trash",
                style: .prominent(AppPalette.amber),
                action: onTrash
            )
            .disabled(isBusy)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? AppPalette.amber.opacity(0.15) : AppPalette.secondaryCard.opacity(0.7))
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
