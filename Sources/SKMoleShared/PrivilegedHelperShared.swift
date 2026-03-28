import Foundation

public enum PrivilegedHelperConstants {
    public static let daemonLabel = "com.siveesh.skmole.privilegedhelper"
    public static let plistName = "com.siveesh.skmole.privilegedhelper.plist"
    public static let helperExecutableName = "com.siveesh.skmole.privilegedhelper"
    public static let bundleProgram = "Contents/Library/LaunchServices/\(helperExecutableName)"
}

public enum MenuBarHelperConstants {
    public static let bundleIdentifier = "com.siveesh.skmole.menubar"
    public static let executableName = "SK Mole Companion"
    public static let displayName = "SK Mole Companion"
    public static let bundleRelativePath = "Contents/Library/LoginItems/\(displayName).app"
    public static let mainAppBundleIdentifier = "com.siveesh.skmole"
    public static let mainAppURLScheme = "skmole"
}

public enum PrivilegedMaintenanceTask: String, CaseIterable, Identifiable, Sendable {
    case flushDNSCache
    case freePurgeableSpace
    case runPeriodicDaily

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .flushDNSCache: "Flush DNS cache"
        case .freePurgeableSpace: "Free up purgeable space"
        case .runPeriodicDaily: "Run daily periodic maintenance"
        }
    }

    public var subtitle: String {
        switch self {
        case .flushDNSCache:
            "Refresh the system resolver and mDNS cache without exposing arbitrary shell access."
        case .freePurgeableSpace:
            "Ask macOS to thin local Time Machine snapshots so APFS can reclaim purgeable space."
        case .runPeriodicDaily:
            "Run macOS daily housekeeping scripts through the system-maintained periodic tool."
        }
    }

    public var icon: String {
        switch self {
        case .flushDNSCache: "network.badge.shield.half.filled"
        case .freePurgeableSpace: "internaldrive.badge.minus"
        case .runPeriodicDaily: "calendar.badge.clock"
        }
    }

    public var caution: String {
        switch self {
        case .flushDNSCache:
            "Short-lived network lookups may repopulate after the cache refresh."
        case .freePurgeableSpace:
            "This targets local Time Machine snapshots and asks macOS to reclaim up to about 10 GB when possible."
        case .runPeriodicDaily:
            "This can take a while and may touch standard maintenance logs and housekeeping jobs."
        }
    }
}

@objc public protocol PrivilegedHelperXPCProtocol {
    func ping(withReply reply: @escaping (String) -> Void)
    func runTask(identifier: String, withReply reply: @escaping (Bool, String) -> Void)
}
