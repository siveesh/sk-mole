import SwiftUI

struct NetworkInspectorView: View {
    @ObservedObject var model: AppModel
    @State private var selectedMode: NetworkInspectorMode = .processes

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                controls
                interfaceSection
                contentSection
            }
            .padding(28)
        }
    }

    private var header: some View {
        SectionCard(
            title: "Network Inspector",
            subtitle: "A Bandwhich-style, on-demand snapshot of who is talking, who is listening, and which remote hosts are most active, without turning the whole app into a permanent packet tracer.",
            symbol: "network"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ByteFormatting.formatRate(model.metrics.networkDownloadRate))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("current download rate")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 6) {
                        Text(ByteFormatting.formatRate(model.metrics.networkUploadRate))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("current upload rate")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Refresh Snapshot") {
                        Task { await model.refreshNetwork() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.networkBusy)
                }

                if let networkReport = model.networkReport {
                    HStack(spacing: 12) {
                        metric(title: "Processes", value: "\(networkReport.processes.count)", detail: "with network sockets")
                        metric(title: "Connections", value: "\(networkReport.activeConnectionCount)", detail: "active remote links")
                        metric(title: "Listeners", value: "\(networkReport.listeningSocketCount)", detail: networkReport.includesListeningSockets ? "included in this snapshot" : "currently hidden")
                        metric(title: "Hosts", value: "\(networkReport.remoteHosts.count)", detail: "distinct remotes")
                    }
                }

                if let networkError = model.networkError {
                    Text(networkError)
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.rose)
                }
            }
        }
    }

    private var controls: some View {
        SectionCard(
            title: "Snapshot Controls",
            subtitle: "Keep this inspector intentionally on-demand. Change the lens, then refresh when you want a new snapshot.",
            symbol: "slider.horizontal.3"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Picker(
                    "View",
                    selection: $selectedMode
                ) {
                    ForEach(NetworkInspectorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 18) {
                    Toggle(
                        "Resolve hostnames",
                        isOn: Binding(
                            get: { model.networkResolveHostnames },
                            set: { model.networkResolveHostnames = $0 }
                        )
                    )

                    Toggle(
                        "Include listening sockets",
                        isOn: Binding(
                            get: { model.networkIncludeListeningSockets },
                            set: { model.networkIncludeListeningSockets = $0 }
                        )
                    )
                }

                Text("Hostname resolution can be slower. Listening sockets are great for debugging local services, but turning them off gives you a cleaner view of actual remote traffic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var interfaceSection: some View {
        SectionCard(
            title: "Interfaces",
            subtitle: "A lightweight look at which interfaces are up and moving bytes right now.",
            symbol: "dot.radiowaves.left.and.right"
        ) {
            let interfaces = model.networkReport?.interfaces ?? []

            if interfaces.isEmpty {
                Text(model.networkBusy ? "Building interface snapshot..." : "No interface data is available yet.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210, maximum: 280), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(interfaces) { interface in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(interface.name)
                                    .font(.headline)
                                Spacer()
                                Pill(
                                    title: interface.isUp ? "Up" : "Down",
                                    tint: interface.isUp ? AppPalette.accent : AppPalette.amber
                                )
                            }

                            Label("↓ \(ByteFormatting.formatRate(interface.inboundRate))", systemImage: "arrow.down.circle")
                            Label("↑ \(ByteFormatting.formatRate(interface.outboundRate))", systemImage: "arrow.up.circle")

                            Text("Totals: ↓ \(ByteFormatting.format(interface.totalInbound)) • ↑ \(ByteFormatting.format(interface.totalOutbound))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(AppPalette.secondaryCard.opacity(0.72))
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        if model.networkBusy && model.networkReport == nil {
            SectionCard(
                title: "Snapshot",
                subtitle: "Collecting current network state.",
                symbol: "network.badge.shield.half.filled"
            ) {
                ProgressView("Inspecting network state…")
            }
        } else if let networkReport = model.networkReport {
            switch selectedMode {
            case .processes:
                processSection(networkReport)
            case .connections:
                connectionsSection(networkReport)
            case .remoteHosts:
                remoteHostsSection(networkReport)
            }
        } else {
            SectionCard(
                title: "No Snapshot Yet",
                subtitle: "Refresh once to capture the current network state.",
                symbol: "network"
            ) {
                ContentUnavailableView(
                    "No Network Snapshot",
                    systemImage: "network.slash",
                    description: Text("SK Mole only collects this data when you open the section or ask for a refresh.")
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func processSection(_ report: NetworkInspectorReport) -> some View {
        SectionCard(
            title: "Processes",
            subtitle: "Which apps or services currently own the most sockets and how broad their remote reach is.",
            symbol: "bolt.horizontal.circle"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(report.processes) { process in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(process.name)
                                    .font(.headline)
                                Text("PID \(process.pid)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("\(process.connectionCount) socket\(process.connectionCount == 1 ? "" : "s")")
                                .font(.subheadline.weight(.semibold))
                        }

                        Text(process.command)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        HStack(spacing: 12) {
                            statPill("Listeners", "\(process.listeningCount)")
                            statPill("Hosts", "\(process.remoteHostCount)")
                            statPill("Protocols", process.protocols.joined(separator: ", "))
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppPalette.secondaryCard.opacity(0.72))
                    )
                }
            }
        }
    }

    private func connectionsSection(_ report: NetworkInspectorReport) -> some View {
        SectionCard(
            title: "Connections",
            subtitle: "A readable socket-by-socket view with protocol, process, and local-to-remote routing.",
            symbol: "point.3.connected.trianglepath.dotted"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(report.connections) { connection in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(connection.processName)
                                    .font(.headline)
                                Pill(title: connection.protocolName, tint: AppPalette.sky)
                                Pill(title: connection.state, tint: connection.isListening ? AppPalette.amber : AppPalette.accent)
                            }

                            Text(connection.localEndpoint)
                                .font(.subheadline.weight(.semibold))

                            if let remoteEndpoint = connection.remoteEndpoint {
                                Text("→ \(remoteEndpoint)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Listening socket")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text("PID \(connection.pid)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppPalette.secondaryCard.opacity(0.72))
                    )
                }
            }
        }
    }

    private func remoteHostsSection(_ report: NetworkInspectorReport) -> some View {
        SectionCard(
            title: "Remote Hosts",
            subtitle: "The busiest remote endpoints surfaced from the current connection snapshot.",
            symbol: "globe.badge.chevron.backward"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(report.remoteHosts) { host in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(host.host)
                                .font(.headline)
                            Spacer()
                            Text("\(host.connectionCount) connection\(host.connectionCount == 1 ? "" : "s")")
                                .font(.subheadline.weight(.semibold))
                        }

                        Text(host.processNames.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(host.protocolNames.joined(separator: " • "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppPalette.secondaryCard.opacity(0.72))
                    )
                }
            }
        }
    }

    private func metric(title: String, value: String, detail: String) -> some View {
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

    private func statPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(AppPalette.secondaryCard.opacity(0.85))
        )
    }
}
