import Foundation
import SKMoleShared

struct MenuBarActiveAlert: Identifiable, Hashable {
    let rule: MenuBarAlertRule
    let title: String
    let detail: String

    var id: String { rule.id }
}

final class MenuBarAlertEvaluator {
    private var matchedSince: [String: Date] = [:]

    func evaluate(snapshot: MenuBarSnapshot, settings: MenuBarCompanionSettings, now: Date = .now) -> [MenuBarActiveAlert] {
        var active: [MenuBarActiveAlert] = []

        for rule in settings.rules where rule.isEnabled {
            let metricValue = value(for: rule.metric, snapshot: snapshot)
            let matches = switch rule.comparison {
            case .above:
                metricValue >= rule.threshold
            case .below:
                metricValue <= rule.threshold
            }

            if matches {
                let start = matchedSince[rule.id] ?? now
                matchedSince[rule.id] = start
                let elapsed = now.timeIntervalSince(start)

                if elapsed >= Double(max(rule.durationSeconds, 0)) {
                    active.append(
                        MenuBarActiveAlert(
                            rule: rule,
                            title: rule.title,
                            detail: detail(for: rule, snapshot: snapshot)
                        )
                    )
                }
            } else {
                matchedSince.removeValue(forKey: rule.id)
            }
        }

        return active
    }

    private func value(for metric: MenuBarAlertMetric, snapshot: MenuBarSnapshot) -> Double {
        switch metric {
        case .cpuUsage:
            snapshot.cpuUsage
        case .memoryUsage:
            snapshot.memoryUsage
        case .diskFreeRatio:
            snapshot.diskFreeRatio
        case .memoryPressure:
            Double(snapshot.memoryPressureLevel)
        case .thermalState:
            Double(snapshot.thermalStateLevel)
        case .batteryLevel:
            snapshot.batteryLevel ?? 1
        }
    }

    private func detail(for rule: MenuBarAlertRule, snapshot: MenuBarSnapshot) -> String {
        switch rule.metric {
        case .cpuUsage:
            return "CPU is holding at \(Int((snapshot.cpuUsage * 100).rounded()))%, above the \(rule.formattedThreshold) rule."
        case .memoryUsage:
            return "Memory usage is at \(Int((snapshot.memoryUsage * 100).rounded()))%, above the \(rule.formattedThreshold) rule."
        case .diskFreeRatio:
            return "Startup disk free space is down to \(Int((snapshot.diskFreeRatio * 100).rounded()))%, below the \(rule.formattedThreshold) rule."
        case .memoryPressure:
            let title = switch snapshot.memoryPressureLevel {
            case 2: "High"
            case 1: "Elevated"
            default: "Stable"
            }
            return "Memory pressure is \(title), which meets the \(rule.formattedThreshold) rule."
        case .thermalState:
            let title = switch snapshot.thermalStateLevel {
            case 3: "Critical"
            case 2: "Serious"
            case 1: "Fair"
            default: "Nominal"
            }
            return "Thermal state is \(title), which meets the \(rule.formattedThreshold) rule."
        case .batteryLevel:
            let percentage = Int(((snapshot.batteryLevel ?? 0) * 100).rounded())
            return "Battery level is at \(percentage)%, below the \(rule.formattedThreshold) rule."
        }
    }
}
