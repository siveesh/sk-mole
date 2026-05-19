import Foundation
import SKMoleShared

actor OptimizationService {
    static let defaultActions: [OptimizeActionDescriptor] = [
        OptimizeActionDescriptor(
            id: "quicklook",
            title: "Reset Quick Look cache",
            subtitle: "Rebuild the preview cache used for Finder thumbnails and quick previews.",
            icon: "eye",
            executable: "/usr/bin/qlmanage",
            arguments: ["-r", "cache"],
            caution: "Open previews may need a moment to repopulate."
        ),
        OptimizeActionDescriptor(
            id: "launchservices",
            title: "Rebuild Launch Services",
            subtitle: "Refresh the app registration database that powers Open With and file associations.",
            icon: "square.stack.3d.up",
            executable: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            arguments: ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"],
            caution: "Finder may briefly rescan app registrations."
        ),
        OptimizeActionDescriptor(
            id: "finder",
            title: "Refresh Finder",
            subtitle: "Relaunch Finder to flush its live UI cache and refresh file views.",
            icon: "finder",
            executable: "/usr/bin/killall",
            arguments: ["Finder"],
            caution: "Open Finder windows will reopen."
        ),
        OptimizeActionDescriptor(
            id: "dock",
            title: "Refresh Dock",
            subtitle: "Relaunch Dock and Mission Control processes to refresh their runtime state.",
            icon: "dock.rectangle",
            executable: "/usr/bin/killall",
            arguments: ["Dock"],
            caution: "Mission Control and the Dock will momentarily restart."
        )
    ]

    func run(_ action: OptimizeActionDescriptor) async -> OptimizationLog {
        do {
            let result = try await ProcessRunner.run(
                executable: action.executable,
                arguments: action.arguments,
                timeout: 30,
                maxOutputBytes: 1 * 1_024 * 1_024
            )
            return OptimizationLog(
                actionTitle: action.title,
                output: result.output.isEmpty ? "Completed without terminal output." : result.output,
                succeeded: result.terminationStatus == 0,
                timestamp: .now
            )
        } catch {
            return OptimizationLog(
                actionTitle: action.title,
                output: error.localizedDescription,
                succeeded: false,
                timestamp: .now
            )
        }
    }
}
