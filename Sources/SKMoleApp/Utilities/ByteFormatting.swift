import Foundation

enum ByteFormatting {
    static func format(_ bytes: UInt64) -> String {
        format(bytes, allowedUnits: [("TB", 1 << 40), ("GB", 1 << 30), ("MB", 1 << 20), ("KB", 1 << 10)])
    }

    static func formatRate(_ bytesPerSecond: UInt64) -> String {
        "\(format(bytesPerSecond, allowedUnits: [("GB", 1 << 30), ("MB", 1 << 20), ("KB", 1 << 10)]))/s"
    }

    private static func format(_ bytes: UInt64, allowedUnits: [(String, UInt64)]) -> String {
        guard bytes >= 1_024 else {
            return "\(bytes) bytes"
        }

        guard let unit = allowedUnits.first(where: { bytes >= $0.1 }) ?? allowedUnits.last else {
            return "\(bytes) bytes"
        }
        let value = Double(bytes) / Double(unit.1)
        let formatted = value >= 10 || value.rounded() == value
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(formatted) \(unit.0)"
    }
}
