import Foundation

struct ScanProgress: Hashable {
    let title: String
    let detail: String
    let completedUnits: Int
    let totalUnits: Int

    var fractionComplete: Double {
        guard totalUnits > 0 else { return 0 }
        return min(1, max(0, Double(completedUnits) / Double(totalUnits)))
    }

    var statusLine: String {
        guard totalUnits > 0 else {
            return detail
        }

        return "\(detail) (\(completedUnits)/\(totalUnits))"
    }
}
