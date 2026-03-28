import SwiftUI

@main
struct SKMoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("SK Mole", id: "main-window") {
            RootView(model: model)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) { }
            MoleCommands(model: model)
        }

        Settings {
            SettingsView(model: model)
        }

        Window("About SK Mole", id: "about-window") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 440, height: 420)
    }
}
