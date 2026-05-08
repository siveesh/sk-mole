import SwiftUI

struct StartupItemsSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SectionCard(
            title: "Startup Items",
            subtitle: "Review launch agents that start with your account and disable noisy user items without touching system-wide services.",
            symbol: "person.crop.circle.badge.plus"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("\(model.startupItems.count) items found")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Refresh") {
                        Task { await model.refreshStartupItems() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.startupItemsBusy)

                    if model.startupItemsBusy {
                        ProgressView()
                    }
                }

                if let startupItemsError = model.startupItemsError {
                    Text(startupItemsError)
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.rose)
                }

                if model.startupItems.isEmpty && !model.startupItemsBusy {
                    Text("No startup items were found in the standard launch agent locations.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.startupItemsByKind, id: \.0) { kind, items in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(kind.title, systemImage: kind.symbol)
                                    .font(.headline)
                                Spacer()
                                Text("\(items.count)")
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(items) { item in
                                StartupItemRow(item: item, model: model)
                            }
                        }
                        .padding(16)
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

private struct StartupItemRow: View {
    let item: StartupItem
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.kind.symbol)
                .foregroundStyle(item.canToggle ? AppPalette.sky : AppPalette.amber)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.headline)

                Text(item.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let program = item.program {
                    Text(program)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Pill(title: item.stateTitle, tint: pillTint)

            ActionIconButton(symbol: "eye", label: "Reveal \(item.displayName)") {
                model.reveal(item.url)
            }

            if item.canToggle {
                Button(toggleTitle) {
                    Task {
                        if item.isDisabled {
                            await model.enableStartupItem(item)
                        } else {
                            await model.disableStartupItem(item)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.startupItemBusyID == item.id)
            }
        }
    }

    private var detailLine: String {
        var parts: [String] = [item.stateDetail]
        if item.runsAtLoad {
            parts.append("Runs at load")
        }
        if item.keepAlive {
            parts.append("KeepAlive")
        }
        return parts.joined(separator: " • ")
    }

    private var toggleTitle: String {
        item.isDisabled ? "Enable" : "Disable"
    }

    private var pillTint: Color {
        if !item.canToggle {
            return AppPalette.amber
        }

        if item.isDisabled {
            return AppPalette.rose
        }

        return item.isLoaded ? AppPalette.accent : AppPalette.sky
    }
}
