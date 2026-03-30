import SwiftUI

struct SmartCareView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                quickActions
                exportCenter

                if model.recommendedActions.isEmpty {
                    SectionCard(
                        title: "No urgent recommendations",
                        subtitle: "SK Mole has enough recent scan data to say the Mac looks steady right now.",
                        symbol: "checkmark.circle"
                    ) {
                        Text("Run the individual sections anytime if you want a fresh cleanup, uninstall, or storage pass.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(model.recommendationsByPriority, id: \.0) { priority, actions in
                        if !actions.isEmpty {
                            prioritySection(priority, actions: actions)
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private var header: some View {
        SectionCard(
            title: "Recommended Actions",
            subtitle: "A guided pass across cleanup, storage pressure, permissions, and uninstall opportunities so you can make progress without hunting through each tab first.",
            symbol: "sparkles.rectangle.stack.fill"
        ) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(model.smartCareScore)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("smart care score")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("\(model.recommendedActions.count)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("active recommendations")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Refresh Inputs") {
                    Task { await model.refreshSmartCareInputs() }
                }
                .buttonStyle(.borderedProminent)

                Button("Export Dry Run") {
                    Task { await model.exportDryRunReport() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var exportCenter: some View {
        SectionCard(
            title: "Export Center",
            subtitle: "Glances-style exporter plugins keep richer outputs available without front-loading the work at startup.",
            symbol: "square.and.arrow.up.on.square"
        ) {
            ExportPluginGridView(plugins: model.availableExportPlugins) { pluginID in
                Task { await model.export(using: pluginID) }
            }
        }
    }

    private var quickActions: some View {
        SectionCard(
            title: "Quick Actions",
            subtitle: "Jump straight into the most useful maintenance flows without hunting through every section.",
            symbol: "bolt.circle"
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(model.quickActions) { action in
                    Button {
                        Task { await model.performQuickAction(action) }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(action.title, systemImage: action.icon)
                                .font(.headline)
                            Text(action.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(AppPalette.secondaryCard.opacity(0.72))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func prioritySection(_ priority: RecommendedActionPriority, actions: [RecommendedAction]) -> some View {
        SectionCard(
            title: priority.title,
            subtitle: subtitle(for: priority),
            symbol: priority.symbol
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(actions) { action in
                    SmartCareActionRow(action: action) {
                        Task { await model.performRecommendedAction(action) }
                    }
                }
            }
        }
    }

    private func subtitle(for priority: RecommendedActionPriority) -> String {
        switch priority {
        case .urgent:
            "Start here when the Mac is under space or system pressure."
        case .recommended:
            "Safe, high-value wins that meaningfully improve the current state."
        case .optional:
            "Good follow-up work once the main pressure is handled."
        }
    }
}

private struct SmartCareActionRow: View {
    let action: RecommendedAction
    let onPerform: () -> Void

    private var tint: Color {
        switch action.priority {
        case .urgent:
            AppPalette.rose
        case .recommended:
            AppPalette.accent
        case .optional:
            AppPalette.sky
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: action.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(action.title)
                        .font(.headline)
                    Spacer()
                    if let estimatedImpactBytes = action.estimatedImpactBytes {
                        Text(ByteFormatting.format(estimatedImpactBytes))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(action.subtitle)
                    .font(.subheadline.weight(.semibold))

                Text(action.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(action.callToAction, action: onPerform)
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.72))
        )
    }
}
