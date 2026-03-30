import AppKit
import SwiftUI

struct MoleCommands: Commands {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About SK Mole") {
                openWindow(id: "about-window")
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        CommandMenu("Sections") {
            ForEach(SidebarSection.allCases) { section in
                Button(section.title) {
                    open(section)
                }
                .keyboardShortcut(KeyEquivalent(section.shortcutKey), modifiers: .command)
            }
        }

        CommandMenu("Refresh") {
            Button("Refresh Current Section") {
                Task { await model.refreshCurrentSelection() }
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Refresh Menu Bar Summary") {
                Task { await model.refreshFromMenuBar() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandMenu("Quick Actions") {
            Button("Export Dry Run Report") {
                Task { await model.exportDryRunReport() }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Open Homebrew") {
                open(.homebrew)
            }

            Button("Open Network Inspector") {
                open(.network)
            }

            Button("Open Quarantine Review") {
                open(.quarantine)
            }

            Button("Open Hidden Storage Mode") {
                model.setStorageInspectionMode(.hidden)
                open(.storage)
            }

            Button("Review Apps Already in Trash") {
                Task { await model.reviewFirstTrashedApplication() }
                open(.uninstall)
            }
            .disabled(model.trashedApplications.isEmpty)
        }
    }

    private func open(_ section: SidebarSection) {
        model.open(section: section)
        openWindow(id: "main-window")
        NSApp.activate(ignoringOtherApps: true)
    }
}
