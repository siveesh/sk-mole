import Foundation

struct SystemMonitorState {
    var metrics: SystemMetricSnapshot = .placeholder
    var cpuHistory: [MetricHistoryPoint] = []
    var memoryHistory: [MetricHistoryPoint] = []
    var downloadHistory: [MetricHistoryPoint] = []
    var uploadHistory: [MetricHistoryPoint] = []
}

@MainActor
final class SystemMonitorStore: ObservableObject {
    private enum HistoryLimit {
        static let points = 60
    }

    @Published private(set) var state = SystemMonitorState()

    var metrics: SystemMetricSnapshot { state.metrics }
    var cpuHistory: [MetricHistoryPoint] { state.cpuHistory }
    var memoryHistory: [MetricHistoryPoint] { state.memoryHistory }
    var downloadHistory: [MetricHistoryPoint] { state.downloadHistory }
    var uploadHistory: [MetricHistoryPoint] { state.uploadHistory }

    func record(snapshot: SystemMetricSnapshot) {
        var updated = state
        updated.metrics = snapshot
        updated.cpuHistory = Self.appendHistory(updated.cpuHistory, value: snapshot.cpuUsage, date: snapshot.timestamp)
        updated.memoryHistory = Self.appendHistory(updated.memoryHistory, value: snapshot.memoryUsage, date: snapshot.timestamp)
        updated.downloadHistory = Self.appendHistory(updated.downloadHistory, value: Double(snapshot.networkDownloadRate), date: snapshot.timestamp)
        updated.uploadHistory = Self.appendHistory(updated.uploadHistory, value: Double(snapshot.networkUploadRate), date: snapshot.timestamp)
        state = updated
    }

    private static func appendHistory(_ points: [MetricHistoryPoint], value: Double, date: Date) -> [MetricHistoryPoint] {
        var updated = points
        updated.append(MetricHistoryPoint(timestamp: date, value: value))

        if updated.count > HistoryLimit.points {
            updated.removeFirst(updated.count - HistoryLimit.points)
        }

        return updated
    }
}
