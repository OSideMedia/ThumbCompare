import SwiftUI

struct SettingsView: View {
    // API key is entered here in-app and persisted to Keychain via AppState.saveSettings().
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YouTube API Settings")
                .font(.title3.weight(.semibold))

            Text("Insert your YouTube Data API v3 key. It is stored securely in Keychain.")
                .foregroundStyle(.secondary)

            SecureField("API Key", text: $appState.apiKey)
                .textFieldStyle(.roundedBorder)

            Toggle("Enable search fallback when forHandle fails (uses more API quota)", isOn: $appState.useSearchFallback)

            HStack {
                Spacer()
                Button("Save") {
                    appState.saveSettings()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
