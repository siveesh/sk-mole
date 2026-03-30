import Darwin
import Foundation

actor NetworkInspectorService {
    private struct InterfaceSample {
        let inbound: UInt64
        let outbound: UInt64
    }

    private struct ConnectionBuilder {
        var pid: Int32 = 0
        var processName = ""
        var command = ""
        var addressFamily = ""
        var protocolName = ""
        var localEndpoint = ""
        var remoteEndpoint: String?
        var state = "UNKNOWN"
    }

    private var previousInterfaceTotals: [String: InterfaceSample] = [:]
    private var previousInterfaceDate = Date.distantPast

    func scan(resolveHostnames: Bool, includeListening: Bool) async throws -> NetworkInspectorReport {
        let interfaces = readInterfaces()
        let capturedAt = Date()
        var connections = try await readConnections(resolveHostnames: resolveHostnames)

        if !includeListening {
            connections.removeAll(where: \.isListening)
        }

        return NetworkInspectorReport(
            capturedAt: capturedAt,
            resolvesHostnames: resolveHostnames,
            includesListeningSockets: includeListening,
            interfaces: interfaces,
            processes: processSummaries(from: connections),
            connections: connections,
            remoteHosts: remoteHostSummaries(from: connections)
        )
    }

    private func readInterfaces() -> [NetworkInterfaceSummary] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else {
            return []
        }

        defer { freeifaddrs(pointer) }

        let now = Date()
        let elapsed = max(now.timeIntervalSince(previousInterfaceDate), 1)
        var currentTotals: [String: InterfaceSample] = [:]
        var summaries: [NetworkInterfaceSummary] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let current = cursor {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            defer { cursor = interface.ifa_next }

            guard
                let name = interface.ifa_name.map({ String(cString: $0) }),
                let address = interface.ifa_addr,
                address.pointee.sa_family == UInt8(AF_LINK),
                (flags & IFF_LOOPBACK) == 0,
                let data = interface.ifa_data
            else {
                continue
            }

            let networkData = data.assumingMemoryBound(to: if_data.self).pointee
            let sample = InterfaceSample(
                inbound: UInt64(networkData.ifi_ibytes),
                outbound: UInt64(networkData.ifi_obytes)
            )
            currentTotals[name] = sample

            let previous = previousInterfaceTotals[name]
            let inboundDelta = previous.map { sample.inbound > $0.inbound ? sample.inbound - $0.inbound : 0 } ?? 0
            let outboundDelta = previous.map { sample.outbound > $0.outbound ? sample.outbound - $0.outbound : 0 } ?? 0

            summaries.append(
                NetworkInterfaceSummary(
                    name: name,
                    inboundRate: UInt64(Double(inboundDelta) / elapsed),
                    outboundRate: UInt64(Double(outboundDelta) / elapsed),
                    totalInbound: sample.inbound,
                    totalOutbound: sample.outbound,
                    isUp: (flags & IFF_UP) != 0
                )
            )
        }

        previousInterfaceTotals = currentTotals
        previousInterfaceDate = now

        return summaries.sorted { left, right in
            if left.isUp != right.isUp {
                return left.isUp && !right.isUp
            }

            let leftRate = left.inboundRate + left.outboundRate
            let rightRate = right.inboundRate + right.outboundRate
            if leftRate != rightRate {
                return leftRate > rightRate
            }

            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    private func readConnections(resolveHostnames: Bool) async throws -> [NetworkConnectionSnapshot] {
        let output = try await ProcessExecutor.run(
            executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: lsofArguments(resolveHostnames: resolveHostnames)
        )

        return parseConnections(from: output)
    }

    private func lsofArguments(resolveHostnames: Bool) -> [String] {
        var arguments = ["-FpcnPTt", "-iTCP", "-iUDP"]

        if !resolveHostnames {
            arguments.insert("-nP", at: 0)
        } else {
            arguments.insert("-P", at: 0)
        }

        return arguments
    }

    private func parseConnections(from output: String) -> [NetworkConnectionSnapshot] {
        var connections: [NetworkConnectionSnapshot] = []
        var currentPID: Int32 = 0
        var currentCommand = ""
        var currentBuilder: ConnectionBuilder?

        func flushBuilder() {
            guard let builder = currentBuilder, !builder.protocolName.isEmpty, !builder.localEndpoint.isEmpty else {
                currentBuilder = nil
                return
            }

            connections.append(
                NetworkConnectionSnapshot(
                    pid: builder.pid,
                    processName: builder.processName,
                    command: builder.command,
                    protocolName: builder.protocolName,
                    addressFamily: builder.addressFamily,
                    localEndpoint: builder.localEndpoint,
                    remoteEndpoint: builder.remoteEndpoint,
                    state: builder.state
                )
            )
            currentBuilder = nil
        }

        for rawLine in output.split(whereSeparator: \.isNewline) {
            guard let prefix = rawLine.first else {
                continue
            }

            let payload = String(rawLine.dropFirst())

            switch prefix {
            case "p":
                flushBuilder()
                currentPID = Int32(payload) ?? 0
            case "c":
                currentCommand = payload
            case "f":
                flushBuilder()
                currentBuilder = ConnectionBuilder(
                    pid: currentPID,
                    processName: currentCommand,
                    command: currentCommand
                )
            case "t":
                currentBuilder?.addressFamily = payload
            case "P":
                currentBuilder?.protocolName = payload
            case "n":
                let parts = payload.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
                if payload.contains("->") {
                    let segments = payload.components(separatedBy: "->")
                    currentBuilder?.localEndpoint = segments.first ?? payload
                    currentBuilder?.remoteEndpoint = segments.count > 1 ? segments[1] : nil
                } else {
                    currentBuilder?.localEndpoint = payload
                    currentBuilder?.remoteEndpoint = nil
                }
                _ = parts
            case "T":
                if payload.hasPrefix("ST=") {
                    currentBuilder?.state = String(payload.dropFirst(3))
                }
            default:
                continue
            }
        }

        flushBuilder()

        return connections.sorted { left, right in
            if left.processName.localizedCaseInsensitiveCompare(right.processName) != .orderedSame {
                return left.processName.localizedCaseInsensitiveCompare(right.processName) == .orderedAscending
            }

            if left.isListening != right.isListening {
                return !left.isListening && right.isListening
            }

            return left.localEndpoint.localizedCaseInsensitiveCompare(right.localEndpoint) == .orderedAscending
        }
    }

    private func processSummaries(from connections: [NetworkConnectionSnapshot]) -> [NetworkProcessSummary] {
        Dictionary(grouping: connections, by: \.pid)
            .values
            .compactMap { group in
                guard let first = group.first else { return nil }
                return NetworkProcessSummary(
                    pid: first.pid,
                    name: first.processName,
                    command: first.command,
                    connectionCount: group.count,
                    listeningCount: group.filter(\.isListening).count,
                    remoteHostCount: Set(group.compactMap(\.remoteHostKey)).count,
                    protocols: Array(Set(group.map(\.protocolName))).sorted()
                )
            }
            .sorted { left, right in
                if left.connectionCount != right.connectionCount {
                    return left.connectionCount > right.connectionCount
                }

                if left.remoteHostCount != right.remoteHostCount {
                    return left.remoteHostCount > right.remoteHostCount
                }

                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
    }

    private func remoteHostSummaries(from connections: [NetworkConnectionSnapshot]) -> [NetworkRemoteHostSummary] {
        Dictionary(grouping: connections.compactMap { connection -> (String, NetworkConnectionSnapshot)? in
            guard let remoteHost = connection.remoteHostKey, !remoteHost.isEmpty, remoteHost != "*" else {
                return nil
            }

            return (remoteHost, connection)
        }, by: \.0)
        .compactMap { host, group in
            let entries = group.map(\.1)
            return NetworkRemoteHostSummary(
                host: host,
                connectionCount: entries.count,
                processNames: Array(Set(entries.map(\.processName))).sorted(),
                protocolNames: Array(Set(entries.map(\.protocolName))).sorted()
            )
        }
        .sorted { left, right in
            if left.connectionCount != right.connectionCount {
                return left.connectionCount > right.connectionCount
            }

            return left.host.localizedCaseInsensitiveCompare(right.host) == .orderedAscending
        }
    }
}

private enum ProcessExecutor {
    static func run(executableURL: URL, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let error = errorPipe.fileHandleForReading.readDataToEndOfFile()

            guard process.terminationStatus == 0 || !output.isEmpty else {
                let message = String(data: error, encoding: .utf8) ?? "Network inspector command failed."
                throw NSError(
                    domain: "SKMole.NetworkInspector",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }

            return String(decoding: output, as: UTF8.self)
        }.value
    }
}
