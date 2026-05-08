import Foundation

public enum SharedMemoryPressureLevel: Int, Codable, Hashable, Sendable {
    case nominal = 0
    case elevated = 1
    case high = 2

    public var title: String {
        switch self {
        case .nominal: "Stable"
        case .elevated: "Elevated"
        case .high: "High"
        }
    }

    public static func classify(
        available: UInt64,
        total: UInt64,
        swapUsed: UInt64,
        compressed: UInt64
    ) -> SharedMemoryPressureLevel {
        guard total > 0 else {
            return .nominal
        }

        let availableRatio = Double(available) / Double(total)
        let compressedRatio = Double(compressed) / Double(total)
        let gigabyte = Double(1_024 * 1_024 * 1_024)

        if availableRatio < 0.05
            || (availableRatio < 0.10 && (Double(swapUsed) >= 4 * gigabyte || compressedRatio > 0.18)) {
            return .high
        }

        if Double(swapUsed) >= gigabyte || availableRatio < 0.16 || compressedRatio > 0.12 {
            return .elevated
        }

        return .nominal
    }
}
