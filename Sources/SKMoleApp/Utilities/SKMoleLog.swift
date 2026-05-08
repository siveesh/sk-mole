import Foundation
import OSLog

enum SKMoleLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.siveesh.skmole"

    static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
    static let sidebar = Logger(subsystem: subsystem, category: "Sidebar")
    static let scans = Logger(subsystem: subsystem, category: "Scans")
    static let uninstall = Logger(subsystem: subsystem, category: "Uninstall")
    static let processes = Logger(subsystem: subsystem, category: "Processes")
    static let maintenance = Logger(subsystem: subsystem, category: "Maintenance")
    static let permissions = Logger(subsystem: subsystem, category: "Permissions")
    static let guardrails = Logger(subsystem: subsystem, category: "Guardrails")
}
