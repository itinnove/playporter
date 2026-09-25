import SwiftUI

@main
struct PlayporterApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 460, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Rechercher les mises à jour…") {
                    model.checkForUpdates(silent: false)
                }
            }
        }
    }
}
