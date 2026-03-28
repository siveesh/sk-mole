import Foundation

struct PrivilegedHelperState: Hashable {
    var summary: String
    var detail: String
    var isEnabled: Bool
    var requiresApproval: Bool

    static let unavailable = PrivilegedHelperState(
        summary: "Not registered",
        detail: "Build and register the helper to unlock admin-only maintenance tasks.",
        isEnabled: false,
        requiresApproval: false
    )
}
