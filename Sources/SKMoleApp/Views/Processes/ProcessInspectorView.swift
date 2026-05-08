import SwiftUI
import SKMoleShared

struct ProcessInspectorView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let processInspectorError = model.processInspectorError {
                    Text(processInspectorError)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppPalette.rose)
                        )
                }

                SectionCard(
                    title: "Active processes",
                    subtitle: "An on-demand snapshot sorted by CPU, memory, or name. SK Mole only allows graceful termination for your own non-system processes.",
                    symbol: "list.bullet.rectangle.portrait"
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            TextField("Search processes", text: $model.processSearch)
                                .textFieldStyle(.roundedBorder)

                            Picker(
                                "Sort",
                                selection: Binding(
                                    get: { model.processSortMode },
                                    set: { model.processSortMode = $0 }
                                )
                            ) {
                                ForEach(ProcessSortMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 240)

                            Button("Refresh") {
                                Task { await model.refreshProcesses() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.processInspectorBusy)
                        }

                        HStack(spacing: 18) {
                            processMetric(
                                title: "Tracked",
                                value: "\(model.processInspectorItems.count)",
                                detail: "processes in the snapshot"
                            )
                            processMetric(
                                title: "Terminable",
                                value: "\(model.processInspectorItems.filter(SystemGuard.canTerminateSnapshot).count)",
                                detail: "user-owned and non-system"
                            )
                            if let top = model.filteredProcessInspectorItems.first {
                                processMetric(
                                    title: "Top CPU",
                                    value: top.name,
                                    detail: String(format: "%.1f%% CPU", top.cpuPercent)
                                )
                            }
                        }

                        if model.processInspectorBusy {
                            ProgressView()
                        }

                        if model.filteredProcessInspectorItems.isEmpty, !model.processInspectorBusy {
                            ContentUnavailableView(
                                "No Matching Processes",
                                systemImage: "list.bullet.rectangle",
                                description: Text("Try a different filter or refresh the snapshot.")
                            )
                            .frame(minHeight: 320)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(model.filteredProcessInspectorItems.prefix(80), id: \.id) { process in
                                    ProcessInspectorRow(model: model, process: process)
                                }
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
            title: "Process inspector",
            subtitle: "A MacOptimizer-style process surface built on native process sampling instead of shelling out. Use it to spot CPU hogs, RAM-heavy work, and background tasks that no longer need to run.",
            symbol: "waveform.path.ecg.rectangle"
        ) {
            Text("SK Mole sends a normal terminate request only. It does not force-kill system processes, root-owned daemons, or its own helper apps from here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func processMetric(title: String, value: String, detail: String) -> some View {
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
}

private struct ProcessInspectorRow: View {
    @ObservedObject var model: AppModel
    let process: NativeProcessActivity

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(process.name)
                        .font(.headline)

                    if SystemGuard.canTerminateSnapshot(process) {
                        Pill(title: "Terminable", tint: AppPalette.accent)
                    } else {
                        Pill(title: "Protected", tint: AppPalette.amber)
                    }
                }

                Text(process.command)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("PID \(process.pid)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f%% CPU", process.cpuPercent))
                    .font(.subheadline.weight(.semibold))
                Text(ByteFormatting.format(process.memoryBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if FileManager.default.fileExists(atPath: process.command) {
                ActionIconButton(symbol: "eye", label: "Reveal \(process.name)") {
                    model.reveal(URL(fileURLWithPath: process.command))
                }
            }

            ActionIconButton(
                symbol: "stop.circle",
                label: "Terminate \(process.name)",
                style: .prominent(AppPalette.amber)
            ) {
                Task { await model.terminateProcess(process) }
            }
            .disabled(!SystemGuard.canTerminateSnapshot(process) || model.processTerminationBusyPID == process.pid)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppPalette.secondaryCard.opacity(0.7))
        )
    }
}
