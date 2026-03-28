import SwiftUI

struct CleanupView: View {
    @ObservedObject var model: AppModel
    @State private var selectedCandidateIDs: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let cleanupError = model.cleanupError {
                    errorBanner(cleanupError)
                }

                ForEach(model.cleanupCategories) { category in
                    CleanupCategoryCard(
                        category: category,
                        selectedCount: selectedCandidates(in: category).count,
                        selectedIDs: selectedCandidateIDs,
                        isBusy: model.cleanupBusy,
                        onReveal: model.reveal,
                        onToggleSelection: { candidate in
                            toggleSelection(for: candidate)
                        },
                        onClearSelection: {
                            clearSelection(in: category)
                        },
                        onTrashCandidate: { candidate in
                            Task {
                                await model.trash(candidate)
                                selectedCandidateIDs.remove(candidate.id)
                            }
                        },
                        onTrashSelected: {
                            Task {
                                let candidates = selectedCandidates(in: category)
                                await model.trashCleanupCandidates(candidates)
                                clearSelection(in: category)
                            }
                        },
                        onTrashCategory: {
                            Task {
                                await model.trash(category)
                                clearSelection(in: category)
                            }
                        }
                    )
                }
            }
            .padding(28)
        }
        .onChange(of: model.cleanupCategories.flatMap(\.candidates).map(\.id)) { _, ids in
            selectedCandidateIDs = selectedCandidateIDs.intersection(Set(ids))
        }
    }

    private var header: some View {
        SectionCard(
            title: "Cleanup preview",
            subtitle: "Nothing is deleted blindly. Each candidate is sized first, filtered through path guards, and moved to Trash instead of being hard-deleted.",
            symbol: "sparkles.rectangle.stack"
        ) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ByteFormatting.format(model.cleanupBytes))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("estimated reclaimable space")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Scan Again") {
                    Task { await model.refreshCleanup() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.cleanupBusy)

                if model.cleanupBusy {
                    ProgressView()
                        .controlSize(.large)
                }
            }

            if let cleanupProgress = model.cleanupProgress {
                InlineScanProgressView(progress: cleanupProgress, tint: AppPalette.accent)
            }
        }
    }

    private func selectedCandidates(in category: CleanupCategorySummary) -> [CleanupCandidate] {
        category.candidates.filter { selectedCandidateIDs.contains($0.id) && $0.safetyLevel != .protected }
    }

    private func toggleSelection(for candidate: CleanupCandidate) {
        if selectedCandidateIDs.contains(candidate.id) {
            selectedCandidateIDs.remove(candidate.id)
        } else {
            selectedCandidateIDs.insert(candidate.id)
        }
    }

    private func clearSelection(in category: CleanupCategorySummary) {
        let categoryIDs = Set(category.candidates.map(\.id))
        selectedCandidateIDs.subtract(categoryIDs)
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

private struct CleanupCategoryCard: View {
    let category: CleanupCategorySummary
    let selectedCount: Int
    let selectedIDs: Set<String>
    let isBusy: Bool
    let onReveal: (URL) -> Void
    let onToggleSelection: (CleanupCandidate) -> Void
    let onClearSelection: () -> Void
    let onTrashCandidate: (CleanupCandidate) -> Void
    let onTrashSelected: () -> Void
    let onTrashCategory: () -> Void

    var body: some View {
        SectionCard(
            title: category.title,
            subtitle: category.subtitle,
            symbol: category.icon
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Pill(title: category.safetyLevel.title, tint: tint)
                    Text(ByteFormatting.format(category.totalBytes))
                        .font(.headline)
                    Spacer()
                    Text("\(selectedCount) selected")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Button("Clear Selection", action: onClearSelection)
                        .buttonStyle(.bordered)
                        .disabled(selectedCount == 0 || isBusy)
                    Button(action: onTrashSelected) {
                        Label("Move Selected to Trash", systemImage: "trash")
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedCount == 0 || isBusy)
                    Button(action: onTrashCategory) {
                        Label("Move Category to Trash", systemImage: "trash")
                    }
                        .buttonStyle(.bordered)
                        .disabled(category.candidates.isEmpty || isBusy)
                }

                if category.candidates.isEmpty {
                    Text("No reclaimable items found in this section right now.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(category.candidates.prefix(8)) { candidate in
                        CleanupCandidateRow(
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
    }

    private var tint: Color {
        switch category.safetyLevel {
        case .safe:
            AppPalette.accent
        case .review:
            AppPalette.amber
        case .protected:
            AppPalette.rose
        }
    }
}

private struct CleanupCandidateRow: View {
    let candidate: CleanupCandidate
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
            .disabled(candidate.safetyLevel == .protected || isBusy)

            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.displayName)
                    .font(.headline)
                Text("\(ByteFormatting.format(candidate.sizeBytes)) • \(DateFormatting.relativeString(from: candidate.lastModified))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ActionIconButton(symbol: "eye", label: "Reveal \(candidate.displayName)", action: onReveal)

            ActionIconButton(
                symbol: "trash",
                label: "Move \(candidate.displayName) to Trash",
                style: .prominent(AppPalette.rose),
                action: onTrash
            )
                .disabled(candidate.safetyLevel == .protected || isBusy)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.7))
        )
    }
}
