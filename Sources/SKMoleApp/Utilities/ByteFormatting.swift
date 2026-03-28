import Foundation

enum ByteFormatting {
    private static func bytesFormatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }

    private static func speedFormatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }

    static func format(_ bytes: UInt64) -> String {
        bytesFormatter().string(fromByteCount: Int64(bytes))
    }

    static func formatRate(_ bytesPerSecond: UInt64) -> String {
        "\(speedFormatter().string(fromByteCount: Int64(bytesPerSecond)))/s"
    }
}
