import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            switch appState.currentScreen {
            case .setup:
                SetupView()
            case .compare:
                CompareView()
            }
        }
    }
}
