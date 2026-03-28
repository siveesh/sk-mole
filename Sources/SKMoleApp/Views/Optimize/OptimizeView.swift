import SwiftUI
import SKMoleShared

struct OptimizeView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 18)], spacing: 18) {
                    ForEach(model.optimizeActions) { action in
                        SectionCard(
                            title: action.title,
                            subtitle: action.subtitle,
                            symbol: action.icon
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(action.caution)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Button("Run Action") {
                                    Task { await model.runOptimization(action) }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.optimizationBusyActionID == action.id)

                                if model.optimizationBusyActionID == action.id {
                                    ProgressView()
                                }
                            }
                        }
                    }
                }

                helperSection

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18)], spacing: 18) {
                    ForEach(model.privilegedMaintenanceTasks) { task in
                        adminTaskCard(task)
                    }
                }

                SectionCard(
                    title: "Recent action log",
                    subtitle: "Execution output from service refresh commands run inside the current session.",
                    symbol: "terminal"
                ) {
                    if model.optimizationLogs.isEmpty {
                        Text("No optimization actions have been run yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(model.optimizationLogs) { log in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(log.actionTitle)
                                            .font(.headline)
                                        Spacer()
                                        Pill(
                                            title: log.succeeded ? "Succeeded" : "Failed",
                                            tint: log.succeeded ? AppPalette.accent : AppPalette.rose
                                        )
                                    }
                                    Text(log.output.trimmingCharacters(in: .whitespacesAndNewlines))
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
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
            .padding(28)
        }
    }

    private var header: some View {
        SectionCard(
            title: "Refresh and rebuild",
            subtitle: "These actions focus on low-risk user-facing service refreshes. Admin-only maintenance stays isolated behind a separate helper instead of elevating the main app.",
            symbol: "bolt.badge.clock"
        ) {
            Text("Use this section after cleanup or uninstall work to refresh previews, file registrations, and shell-visible system services.")
                .foregroundStyle(.secondary)
        }
    }

    private var helperSection: some View {
        SectionCard(
            title: "Privileged helper",
            subtitle: "Admin-only maintenance is isolated into a narrow launch daemon with a fixed task allow-list and no arbitrary command execution.",
            symbol: "lock.shield"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Pill(
                        title: model.privilegedHelperState.summary,
                        tint: model.privilegedHelperState.isEnabled ? AppPalette.accent : AppPalette.amber
                    )
                    Text("Reachability: \(model.privilegedHelperReachability)")
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Text(model.privilegedHelperState.detail)
                    .foregroundStyle(.secondary)

                if let privilegedHelperError = model.privilegedHelperError {
                    Text(privilegedHelperError)
                        .foregroundStyle(AppPalette.rose)
                        .font(.subheadline)
                }

                HStack(spacing: 12) {
                    Button("Register Helper") {
                        Task { await model.registerPrivilegedHelper() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.privilegedHelperBusy)

                    Button("Refresh Status") {
                        Task { await model.refreshPrivilegedHelperState() }
                    }
                    .buttonStyle(.bordered)

                    Button("Unregister Helper") {
                        Task { await model.unregisterPrivilegedHelper() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.privilegedHelperBusy || !model.privilegedHelperState.isEnabled)

                    if model.privilegedHelperBusy {
                        ProgressView()
                    }
                }
            }
        }
    }

    private func adminTaskCard(_ task: PrivilegedMaintenanceTask) -> some View {
        SectionCard(
            title: task.title,
            subtitle: task.subtitle,
            symbol: task.icon
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(task.caution)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !model.privilegedHelperState.isEnabled {
                    Text("Register the privileged helper to enable this admin task.")
                        .font(.caption)
                        .foregroundStyle(AppPalette.amber)
                }

                Button("Run Admin Task") {
                    Task { await model.runPrivilegedMaintenance(task) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.privilegedHelperBusyTaskID == task.id || !model.privilegedHelperState.isEnabled)

                if model.privilegedHelperBusyTaskID == task.id {
                    ProgressView()
                }
            }
        }
    }
}
