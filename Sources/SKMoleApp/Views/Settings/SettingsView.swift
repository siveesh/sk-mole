import SwiftUI
import SKMoleShared

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionCard(
                    title: "Startup",
                    subtitle: "Keep SK Mole light on launch and decide what the first main window should focus on.",
                    symbol: "sparkles.tv"
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker(
                            "Main window startup",
                            selection: Binding(
                                get: { model.startupPreference },
                                set: { model.startupPreference = $0 }
                            )
                        ) {
                            ForEach(StartupPreference.allCases) { preference in
                                Text(preference.title).tag(preference)
                            }
                        }

                        Toggle(
                            "Refresh the visible section when it opens",
                            isOn: Binding(
                                get: { model.autoRefreshOnOpen },
                                set: { model.autoRefreshOnOpen = $0 }
                            )
                        )

                        Text("With this off, SK Mole only loads a section the first time you visit it and then reuses the latest scan until you refresh it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SectionCard(
                    title: "Uninstall Depth",
                    subtitle: "Choose how aggressively SK Mole should look for related app leftovers before it builds an uninstall preview.",
                    symbol: "xmark.app"
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker(
                            "Preview depth",
                            selection: Binding(
                                get: { model.uninstallSensitivity },
                                set: { newValue in
                                    model.uninstallSensitivity = newValue
                                    Task { await model.refreshSelectedAppPreviewForSensitivity() }
                                }
                            )
                        ) {
                            ForEach(UninstallSensitivityLevel.allCases) { level in
                                Text(level.title).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(UninstallSensitivityLevel.allCases) { level in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: level == model.uninstallSensitivity ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(level == model.uninstallSensitivity ? AppPalette.accent : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(level.title)
                                            .font(.headline)
                                        Text(level.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                SectionCard(
                    title: "Menu Bar Companion",
                    subtitle: "Optionally run a separate helper app in the menu bar so you can reopen or quit cleanly even after the main window or main process is gone.",
                    symbol: "menubar.rectangle"
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(
                            "Keep the companion enabled",
                            isOn: Binding(
                                get: { model.menuBarCompanionEnabled },
                                set: { model.menuBarCompanionEnabled = $0 }
                            )
                        )

                        HStack {
                            Text(model.menuBarCompanionState.summary)
                                .font(.headline)
                            Spacer()
                            Text(model.menuBarCompanionState.isRunning ? "Running" : "Not running")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(model.menuBarCompanionState.isRunning ? AppPalette.accent.opacity(0.18) : AppPalette.secondaryCard)
                                )
                        }

                        Text(model.menuBarCompanionState.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let menuBarCompanionError = model.menuBarCompanionError {
                            Text(menuBarCompanionError)
                                .font(.caption)
                                .foregroundStyle(AppPalette.amber)
                        }

                        HStack(spacing: 12) {
                            Button("Launch Companion Now") {
                                model.launchMenuBarCompanionNow()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Refresh Status") {
                                model.refreshMenuBarCompanionState()
                            }
                            .buttonStyle(.bordered)

                            Button("Quit Companion") {
                                model.quitMenuBarCompanion()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!model.menuBarCompanionState.isRunning)
                        }
                    }
                }

                SectionCard(
                    title: "Companion Alerts",
                    subtitle: "Tune the status item layout and alert rules so the companion stays useful without becoming noisy.",
                    symbol: "bell.badge"
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Status item style")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Picker(
                                "Status item style",
                                selection: Binding(
                                    get: { model.menuBarCompanionSettings.statusStyle },
                                    set: { newValue in
                                        model.saveMenuBarCompanionSettings { $0.statusStyle = newValue }
                                    }
                                )
                            ) {
                                ForEach(MenuBarStatusStyle.allCases) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Visible metrics")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
                                alignment: .leading,
                                spacing: 10
                            ) {
                                ForEach(MenuBarStatusMetric.allCases) { metric in
                                    Toggle(metric.title, isOn: metricBinding(metric))
                                        .toggleStyle(.switch)
                                }
                            }

                            Text(statusPreviewText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(Array(model.menuBarCompanionSettings.rules.enumerated()), id: \.element.id) { index, rule in
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle(
                                    rule.title,
                                    isOn: Binding(
                                        get: { model.menuBarCompanionSettings.rules[index].isEnabled },
                                        set: { newValue in
                                            model.saveMenuBarCompanionSettings { settings in
                                                settings.rules[index].isEnabled = newValue
                                            }
                                        }
                                    )
                                )

                                Text(rule.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 12) {
                                    Text("Threshold")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    if rule.metric.discreteThresholdOptions.isEmpty {
                                        Slider(
                                            value: Binding(
                                                get: { model.menuBarCompanionSettings.rules[index].threshold },
                                                set: { newValue in
                                                    model.saveMenuBarCompanionSettings { settings in
                                                        settings.rules[index].threshold = newValue
                                                    }
                                                }
                                            ),
                                            in: rule.metric.thresholdRange,
                                            step: rule.metric.thresholdStep
                                        )
                                    } else {
                                        Picker(
                                            "Threshold",
                                            selection: Binding(
                                                get: { model.menuBarCompanionSettings.rules[index].threshold },
                                                set: { newValue in
                                                    model.saveMenuBarCompanionSettings { settings in
                                                        settings.rules[index].threshold = newValue
                                                    }
                                                }
                                            )
                                        ) {
                                            ForEach(rule.metric.discreteThresholdOptions, id: \.value) { option in
                                                Text(option.title).tag(option.value)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                    }

                                    Text(model.menuBarCompanionSettings.rules[index].formattedThreshold)
                                        .font(.caption.weight(.semibold))
                                        .frame(width: 72, alignment: .trailing)
                                }

                                Stepper(
                                    value: Binding(
                                        get: { model.menuBarCompanionSettings.rules[index].durationSeconds },
                                        set: { newValue in
                                            model.saveMenuBarCompanionSettings { settings in
                                                settings.rules[index].durationSeconds = newValue
                                            }
                                        }
                                    ),
                                    in: 0...600,
                                    step: 15
                                ) {
                                    Text("Hold for \(model.menuBarCompanionSettings.rules[index].durationSeconds)s before alerting")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AppPalette.secondaryCard.opacity(0.72))
                            )
                        }

                        Button("Reset Default Rules") {
                            model.resetMenuBarCompanionSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                SectionCard(
                    title: "Permissions",
                    subtitle: "Use one place to revisit onboarding, Full Disk Access guidance, and the helper state without hunting through multiple tabs.",
                    symbol: "lock.shield"
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Full Disk Access")
                                .font(.headline)
                            Spacer()
                            Text(model.fullDiskAccessStatus.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(model.fullDiskAccessStatus.needsAttention ? AppPalette.amber.opacity(0.18) : AppPalette.accent.opacity(0.16))
                                )
                        }

                        Text(model.fullDiskAccessStatus.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Toggle(
                            "Show Full Disk Access reminders",
                            isOn: Binding(
                                get: { model.showFullDiskAccessReminders },
                                set: { model.showFullDiskAccessReminders = $0 }
                            )
                        )

                        HStack(spacing: 12) {
                            Button("Open Privacy & Security") {
                                model.openFullDiskAccessSettings()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Re-check Access") {
                                model.refreshFullDiskAccessStatus()
                            }
                            .buttonStyle(.bordered)

                            Button("Show Onboarding Again") {
                                model.reopenOnboarding()
                            }
                            .buttonStyle(.bordered)
                        }

                        Divider()

                        HStack {
                            Text("Privileged Helper")
                                .font(.headline)
                            Spacer()
                            Text(model.privilegedHelperState.summary)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(model.privilegedHelperState.isEnabled ? AppPalette.accent.opacity(0.16) : AppPalette.amber.opacity(0.18))
                                )
                        }

                        Text(model.privilegedHelperState.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let privilegedHelperError = model.privilegedHelperError {
                            Text(privilegedHelperError)
                                .font(.caption)
                                .foregroundStyle(AppPalette.amber)
                        }
                    }
                }

                SectionCard(
                    title: "Scheduled Maintenance",
                    subtitle: "Run a lightweight scan-and-export cycle on a daily or weekly cadence while SK Mole is running, then save the report to Documents/SK Mole Reports.",
                    symbol: "calendar.badge.clock"
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker(
                            "Schedule",
                            selection: Binding(
                                get: { model.scheduledMaintenanceInterval },
                                set: { model.scheduledMaintenanceInterval = $0 }
                            )
                        ) {
                            ForEach(ScheduledMaintenanceInterval.allCases) { interval in
                                Text(interval.title).tag(interval)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker(
                            "Export format",
                            selection: Binding(
                                get: { model.scheduledMaintenanceExportFormat },
                                set: { model.scheduledMaintenanceExportFormat = $0 }
                            )
                        ) {
                            ForEach(ScheduledMaintenanceExportFormat.allCases) { format in
                                Text(format.title).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(
                            model.lastScheduledMaintenanceRun.map {
                                "Last scheduled run: \(DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short))"
                            } ?? "No scheduled maintenance run has completed yet."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Run Now") {
                                Task { await model.runScheduledMaintenanceNow() }
                            }
                            .buttonStyle(.borderedProminent)

                            Text("These exports are dry-run reports only. SK Mole does not schedule automatic deletion.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SectionCard(
                    title: "Export Plugins",
                    subtitle: "Exporters are loaded only when you use them, so SK Mole can stay richer without paying the startup cost every time.",
                    symbol: "square.and.arrow.up.on.square"
                ) {
                    ExportPluginGridView(plugins: model.availableExportPlugins) { pluginID in
                        Task { await model.export(using: pluginID) }
                    }
                }

                SectionCard(
                    title: "Monitoring Notes",
                    subtitle: "Keep the menu bar useful without turning SK Mole into another heavy background tool, while giving Console enough signal to help with debugging.",
                    symbol: "waveform.path.ecg.rectangle"
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Top-process sampling is throttled to every five seconds to keep overhead low while still showing who is driving CPU and memory spikes.")
                        Text("Process termination is limited to your own non-system processes and uses a normal terminate signal instead of a force kill.")
                        Text("Battery, power source, swap pressure, thermal state, and per-core activity use public macOS APIs. Fine-grained temperatures, fan RPM, and per-app network accounting still need lower-level or non-public data sources.")
                        Text("Key navigation, scan, uninstall, process, and maintenance actions now write through unified logging categories so they are visible in Console under the SK Mole subsystem.")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .frame(width: 700, height: 760)
        .background(AppPalette.canvas)
    }

    private func metricBinding(_ metric: MenuBarStatusMetric) -> Binding<Bool> {
        Binding(
            get: { model.menuBarCompanionSettings.visibleStatusMetrics.contains(metric) },
            set: { isSelected in
                model.saveMenuBarCompanionSettings { settings in
                    var metrics = settings.visibleStatusMetrics

                    if isSelected {
                        if !metrics.contains(metric) {
                            metrics.append(metric)
                        }
                    } else {
                        metrics.removeAll { $0 == metric }
                        if metrics.isEmpty {
                            metrics = [metric]
                        }
                    }

                    settings.visibleStatusMetrics = MenuBarStatusMetric.allCases.filter { metrics.contains($0) }
                }
            }
        )
    }

    private var statusPreviewText: String {
        let metrics = model.menuBarCompanionSettings.visibleStatusMetrics
        let metricNames = metrics.isEmpty ? "CPU" : metrics.map(\.title).joined(separator: ", ")
        return "The companion will surface \(metricNames) using the \(model.menuBarCompanionSettings.statusStyle.title.lowercased()) layout."
    }
}
