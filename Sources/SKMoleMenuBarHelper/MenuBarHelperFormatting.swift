import Foundation

enum MenuBarHelperFormatting {
    private static func bytesFormatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }

    private static func rateFormatter() -> ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        bytesFormatter().string(fromByteCount: Int64(bytes))
    }

    static func formatRate(_ bytesPerSecond: UInt64) -> String {
        "\(rateFormatter().string(fromByteCount: Int64(bytesPerSecond)))/s"
    }
}
