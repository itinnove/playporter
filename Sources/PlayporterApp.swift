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
    }
}
