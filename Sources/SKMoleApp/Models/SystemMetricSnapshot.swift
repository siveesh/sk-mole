import Foundation

enum MemoryPressureState: String, Hashable {
    case nominal
    case elevated
    case high

    var title: String {
        switch self {
        case .nominal: "Stable"
        case .elevated: "Elevated"
        case .high: "High"
        }
    }

    var symbol: String {
        switch self {
        case .nominal: "checkmark.circle"
        case .elevated: "exclamationmark.circle"
        case .high: "exclamationmark.triangle"
        }
    }
}

enum ThermalStateSummary: String, Hashable {
    case nominal
    case fair
    case serious
    case critical

    var title: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        }
    }

    var symbol: String {
        switch self {
        case .nominal: "thermometer.low"
        case .fair: "thermometer.medium"
        case .serious: "thermometer.high"
        case .critical: "flame"
        }
    }
}

struct PowerSourceSnapshot: Hashable {
    let source: String
    let batteryLevel: Double?
    let isCharging: Bool
    let timeRemainingMinutes: Int?
    let lowPowerMode: Bool

    var sourceTitle: String {
        switch source {
        case "Battery Power":
            return "Battery"
        case "AC Power":
            return "AC Power"
        case "UPS Power":
            return "UPS"
        default:
            return source
        }
    }

    var summary: String {
        var parts: [String] = [sourceTitle]

        if let batteryLevel {
            parts.append("\(Int((batteryLevel * 100).rounded()))%")
        }

        if isCharging {
            parts.append("Charging")
        } else if let timeRemainingMinutes, timeRemainingMinutes > 0 {
            let hours = timeRemainingMinutes / 60
            let minutes = timeRemainingMinutes % 60
            if hours > 0 {
                parts.append("\(hours)h \(minutes)m left")
            } else {
                parts.append("\(minutes)m left")
            }
        }

        if lowPowerMode {
            parts.append("Low Power")
        }

        return parts.joined(separator: " • ")
    }
}

struct ProcessActivity: Identifiable, Hashable {
    let pid: Int32
    let name: String
    let command: String
    let cpuPercent: Double
    let memoryBytes: UInt64

    var id: Int32 { pid }
}

struct MetricHistoryPoint: Identifiable, Hashable {
    let timestamp: Date
    let value: Double

    var id: TimeInterval { timestamp.timeIntervalSinceReferenceDate }
}

struct SystemMetricSnapshot {
    var cpuUsage: Double
    var perCoreUsage: [Double]
    var gpuActivity: Double?
    var gpuName: String
    var gpuCores: Int?
    var metalSupport: String
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var memoryCached: UInt64
    var memoryWired: UInt64
    var memoryCompressed: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64
    var memoryPressure: MemoryPressureState
    var diskUsed: UInt64
    var diskTotal: UInt64
    var networkDownloadRate: UInt64
    var networkUploadRate: UInt64
    var powerSource: PowerSourceSnapshot?
    var thermalState: ThermalStateSummary
    var topProcesses: [ProcessActivity]
    var timestamp: Date

    var memoryUsage: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal)
    }

    var diskUsage: Double {
        guard diskTotal > 0 else { return 0 }
        return Double(diskUsed) / Double(diskTotal)
    }

    var swapUsage: Double {
        guard swapTotal > 0 else { return 0 }
        return Double(swapUsed) / Double(swapTotal)
    }

    static let placeholder = SystemMetricSnapshot(
        cpuUsage: 0.18,
        perCoreUsage: [0.14, 0.21, 0.11, 0.27],
        gpuActivity: nil,
        gpuName: "Metal GPU",
        gpuCores: nil,
        metalSupport: "Metal",
        memoryUsed: 8 * 1_024 * 1_024 * 1_024,
        memoryTotal: 32 * 1_024 * 1_024 * 1_024,
        memoryCached: 7 * 1_024 * 1_024 * 1_024,
        memoryWired: 3 * 1_024 * 1_024 * 1_024,
        memoryCompressed: 512 * 1_024 * 1_024,
        swapUsed: 0,
        swapTotal: 0,
        memoryPressure: .nominal,
        diskUsed: 512 * 1_024 * 1_024 * 1_024,
        diskTotal: 1_024 * 1_024 * 1_024 * 1_024,
        networkDownloadRate: 0,
        networkUploadRate: 0,
        powerSource: PowerSourceSnapshot(
            source: "AC Power",
            batteryLevel: nil,
            isCharging: false,
            timeRemainingMinutes: nil,
            lowPowerMode: false
        ),
        thermalState: .nominal,
        topProcesses: [],
        timestamp: .now
    )
}
