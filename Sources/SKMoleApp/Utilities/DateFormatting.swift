import Foundation

enum DateFormatting {
    private static func formatter() -> RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }

    static func relativeString(from date: Date?) -> String {
        guard let date else { return "Unknown" }
        return formatter().localizedString(for: date, relativeTo: .now)
    }
}
