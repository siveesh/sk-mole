import Foundation

struct MenuBarCompanionState: Hashable {
    let summary: String
    let detail: String
    let isRunning: Bool
    let isRegistered: Bool
    let requiresApproval: Bool

    static let unavailable = MenuBarCompanionState(
        summary: "Unavailable",
        detail: "The embedded companion app bundle was not found in this build.",
        isRunning: false,
        isRegistered: false,
        requiresApproval: false
    )
}
