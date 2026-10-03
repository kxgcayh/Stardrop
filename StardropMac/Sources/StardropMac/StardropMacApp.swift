import SwiftUI

@main
struct StardropMacApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .frame(minWidth: 850, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1080, height: 700)
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .appInfo) {
                Button("About Stardrop") {
                    NotificationCenter.default.post(name: .openAbout, object: nil)
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("Game") {
                Button("Launch SMAPI") {
                    NotificationCenter.default.post(name: .launchSmapi, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandMenu("Nexus Mods") {
                Button("Nexus Mods Account...") {
                    NotificationCenter.default.post(name: .openNexus, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .help) {
                Button("Stardrop Documentation") {
                    if let url = URL(string: "https://floogen.gitbook.io/stardrop/") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("GitHub Repository") {
                    if let url = URL(string: "https://github.com/Floogen/Stardrop") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("SMAPI.io") {
                    if let url = URL(string: "https://smapi.io/") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Divider()
                Button("About Stardrop") {
                    NotificationCenter.default.post(name: .openAbout, object: nil)
                }
            }
        }
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("StardropOpenSettings")
    static let launchSmapi = Notification.Name("StardropLaunchSmapi")
    static let openNexus = Notification.Name("StardropOpenNexus")
    static let openAbout = Notification.Name("StardropOpenAbout")
}
