import SwiftUI

@main
struct ThumbCompareApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 1200, minHeight: 760)
        }
        .windowResizability(.contentSize)
    }
}
