import SwiftUI

@main
struct PlayporterApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 420, minHeight: 360)
        }
        .windowResizability(.contentMinSize)
    }
}
