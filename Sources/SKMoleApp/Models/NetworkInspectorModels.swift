import Foundation

enum NetworkInspectorMode: String, CaseIterable, Identifiable, Hashable {
    case processes
    case connections
    case remoteHosts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .processes: "Processes"
        case .connections: "Connections"
        case .remoteHosts: "Remote Hosts"
        }
    }
}

struct NetworkInterfaceSummary: Codable, Identifiable, Hashable {
    let name: String
    let inboundRate: UInt64
    let outboundRate: UInt64
    let totalInbound: UInt64
    let totalOutbound: UInt64
    let isUp: Bool

    var id: String { name }
}

struct NetworkConnectionSnapshot: Codable, Identifiable, Hashable {
    let pid: Int32
    let processName: String
    let command: String
    let protocolName: String
    let addressFamily: String
    let localEndpoint: String
    let remoteEndpoint: String?
    let state: String

    var id: String {
        "\(pid)-\(protocolName)-\(localEndpoint)-\(remoteEndpoint ?? "-")-\(state)"
    }

    var isListening: Bool {
        state == "LISTEN" || remoteEndpoint == nil
    }

    var remoteHostKey: String? {
        guard let remoteEndpoint else {
            return nil
        }

        return NetworkEndpointParsing.hostPart(of: remoteEndpoint)
    }
}

struct NetworkProcessSummary: Codable, Identifiable, Hashable {
    let pid: Int32
    let name: String
    let command: String
    let connectionCount: Int
    let listeningCount: Int
    let remoteHostCount: Int
    let protocols: [String]

    var id: Int32 { pid }
}

struct NetworkRemoteHostSummary: Codable, Identifiable, Hashable {
    let host: String
    let connectionCount: Int
    let processNames: [String]
    let protocolNames: [String]

    var id: String { host }
}

struct NetworkInspectorReport: Codable, Hashable {
    let capturedAt: Date
    let resolvesHostnames: Bool
    let includesListeningSockets: Bool
    let interfaces: [NetworkInterfaceSummary]
    let processes: [NetworkProcessSummary]
    let connections: [NetworkConnectionSnapshot]
    let remoteHosts: [NetworkRemoteHostSummary]

    var activeConnectionCount: Int {
        connections.filter { !$0.isListening }.count
    }

    var listeningSocketCount: Int {
        connections.filter(\.isListening).count
    }
}

enum NetworkEndpointParsing {
    static func hostPart(of endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("["),
           let closing = trimmed.firstIndex(of: "]") {
            return String(trimmed[trimmed.index(after: trimmed.startIndex)..<closing])
        }

        if let lastColon = trimmed.lastIndex(of: ":"),
           trimmed[trimmed.index(after: lastColon)...].allSatisfy(\.isNumber) {
            return String(trimmed[..<lastColon])
        }

        return trimmed
    }
}
