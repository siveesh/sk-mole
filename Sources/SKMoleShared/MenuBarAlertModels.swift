import Foundation

public enum MenuBarAlertMetric: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case cpuUsage
    case memoryUsage
    case diskFreeRatio
    case memoryPressure
    case thermalState
    case batteryLevel

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpuUsage: "CPU usage"
        case .memoryUsage: "Memory usage"
        case .diskFreeRatio: "Startup disk free space"
        case .memoryPressure: "Memory pressure"
        case .thermalState: "Thermal state"
        case .batteryLevel: "Battery level"
        }
    }

    public var symbol: String {
        switch self {
        case .cpuUsage: "cpu"
        case .memoryUsage: "memorychip"
        case .diskFreeRatio: "internaldrive"
        case .memoryPressure: "waveform.path.ecg"
        case .thermalState: "thermometer.medium"
        case .batteryLevel: "battery.50"
        }
    }

    public var defaultComparison: MenuBarAlertComparison {
        switch self {
        case .diskFreeRatio:
            return .below
        case .batteryLevel:
            return .below
        case .cpuUsage, .memoryUsage, .memoryPressure, .thermalState:
            return .above
        }
    }

    public var thresholdStep: Double {
        switch self {
        case .cpuUsage, .memoryUsage, .diskFreeRatio, .batteryLevel:
            return 0.01
        case .memoryPressure, .thermalState:
            return 1
        }
    }

    public var thresholdRange: ClosedRange<Double> {
        switch self {
        case .cpuUsage, .memoryUsage, .diskFreeRatio, .batteryLevel:
            return 0.05...0.95
        case .memoryPressure:
            return 1...2
        case .thermalState:
            return 1...3
        }
    }
}

public enum MenuBarStatusStyle: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case compact
    case combined
    case sensorStrip

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compact: "Compact"
        case .combined: "Combined"
        case .sensorStrip: "Sensor Strip"
        }
    }
}

public enum MenuBarStatusMetric: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case cpu
    case memory
    case network
    case thermal
    case pressure
    case battery
    case diskFree

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        case .thermal: "Thermal"
        case .pressure: "Pressure"
        case .battery: "Battery"
        case .diskFree: "Disk Free"
        }
    }
}

public enum MenuBarAlertComparison: String, Codable, Hashable, Sendable {
    case above
    case below
}

public struct MenuBarAlertRule: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var metric: MenuBarAlertMetric
    public var comparison: MenuBarAlertComparison
    public var threshold: Double
    public var durationSeconds: Int
    public var cooldownMinutes: Int
    public var isEnabled: Bool

    public init(
        id: String = UUID().uuidString,
        metric: MenuBarAlertMetric,
        comparison: MenuBarAlertComparison,
        threshold: Double,
        durationSeconds: Int,
        cooldownMinutes: Int,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.metric = metric
        self.comparison = comparison
        self.threshold = threshold
        self.durationSeconds = durationSeconds
        self.cooldownMinutes = cooldownMinutes
        self.isEnabled = isEnabled
    }

    public var title: String {
        metric.title
    }

    public var formattedThreshold: String {
        switch metric {
        case .cpuUsage, .memoryUsage, .diskFreeRatio, .batteryLevel:
            return Int((threshold * 100).rounded()).formatted(.number) + "%"
        case .memoryPressure:
            return Int(threshold.rounded()) == 2 ? "High" : "Elevated"
        case .thermalState:
            switch Int(threshold.rounded()) {
            case 3:
                return "Critical"
            case 2:
                return "Serious"
            default:
                return "Fair"
            }
        }
    }

    public var summary: String {
        let comparisonText = switch comparison {
        case .above: "above"
        case .below: "below"
        }

        let duration = durationSeconds > 0 ? "\(durationSeconds)s" : "instant"
        return "\(metric.title) \(comparisonText) \(formattedThreshold) for \(duration)"
    }

    public static let defaults: [MenuBarAlertRule] = [
        MenuBarAlertRule(
            id: "cpu-usage",
            metric: .cpuUsage,
            comparison: .above,
            threshold: 0.85,
            durationSeconds: 120,
            cooldownMinutes: 20
        ),
        MenuBarAlertRule(
            id: "memory-usage",
            metric: .memoryUsage,
            comparison: .above,
            threshold: 0.84,
            durationSeconds: 120,
            cooldownMinutes: 20
        ),
        MenuBarAlertRule(
            id: "disk-free",
            metric: .diskFreeRatio,
            comparison: .below,
            threshold: 0.12,
            durationSeconds: 30,
            cooldownMinutes: 60
        ),
        MenuBarAlertRule(
            id: "memory-pressure",
            metric: .memoryPressure,
            comparison: .above,
            threshold: 1,
            durationSeconds: 45,
            cooldownMinutes: 20
        ),
        MenuBarAlertRule(
            id: "thermal-state",
            metric: .thermalState,
            comparison: .above,
            threshold: 2,
            durationSeconds: 30,
            cooldownMinutes: 20
        ),
        MenuBarAlertRule(
            id: "battery-level",
            metric: .batteryLevel,
            comparison: .below,
            threshold: 0.20,
            durationSeconds: 120,
            cooldownMinutes: 30,
            isEnabled: false
        )
    ]
}

public struct MenuBarCompanionSettings: Codable, Hashable, Sendable {
    public var rules: [MenuBarAlertRule]
    public var statusStyle: MenuBarStatusStyle
    public var visibleStatusMetrics: [MenuBarStatusMetric]

    public init(
        rules: [MenuBarAlertRule] = MenuBarAlertRule.defaults,
        statusStyle: MenuBarStatusStyle = .combined,
        visibleStatusMetrics: [MenuBarStatusMetric] = [.cpu, .memory, .thermal]
    ) {
        self.rules = rules
        self.statusStyle = statusStyle
        self.visibleStatusMetrics = visibleStatusMetrics
    }

    public static let `default` = MenuBarCompanionSettings()
}

public final class MenuBarCompanionSettingsStore {
    private let fileURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(fileURL: URL = SharedSupportDirectories.fileURL(named: "companion-settings.json")) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> MenuBarCompanionSettings {
        guard let data = try? Data(contentsOf: fileURL) else {
            return .default
        }

        return (try? decoder.decode(MenuBarCompanionSettings.self, from: data)) ?? .default
    }

    public func save(_ settings: MenuBarCompanionSettings) throws {
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }
}
