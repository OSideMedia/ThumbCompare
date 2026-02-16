import SwiftUI
import UniformTypeIdentifiers

struct SetupView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showSettings = false
    @State private var importA = false
    @State private var importB = false

    var body: some View {
        ZStack {
            Color(red: 0.98, green: 0.98, blue: 0.99)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    HStack(alignment: .top, spacing: 14) {
                        ThumbnailDropZone(title: "Thumbnail A (Required)", image: $appState.myThumbnailA, showImporter: $importA)
                        ThumbnailDropZone(title: "Thumbnail B (Optional)", image: $appState.myThumbnailB, showImporter: $importB)
                    }

                    channelCard
                    handlesCard
                    actionBar

                    if let error = appState.errorMessage {
                        Text(error)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.08)))
                    }

                    if !appState.fetchLogs.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Fetch Log")
                                .font(.headline)
                                .foregroundStyle(Color.black.opacity(0.85))
                            ForEach(appState.fetchLogs, id: \.self) { line in
                                Text(line)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(line.contains("FAILED") ? Color.red : Color.black.opacity(0.62))
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08), lineWidth: 1))
                    }
                }
                .padding(20)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .fileImporter(
            isPresented: $importA,
            allowedContentTypes: [.png, .jpeg, .heic, .tiff, .gif, .image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let first = urls.first {
                appState.myThumbnailA = NSImage(contentsOf: first)
            }
        }
        .fileImporter(
            isPresented: $importB,
            allowedContentTypes: [.png, .jpeg, .heic, .tiff, .gif, .image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let first = urls.first {
                appState.myThumbnailB = NSImage(contentsOf: first)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ThumbCompare")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.9))
                Text("Compare your thumbnail against the latest competitor feed")
                    .font(.subheadline)
                    .foregroundStyle(Color.black.opacity(0.55))
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
        }
    }

    private var channelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Channel")
                .font(.headline)
                .foregroundStyle(Color.black.opacity(0.85))

            TextField("https://youtube.com/@yourchannel or @yourchannel", text: $appState.myChannelInput)
                .textFieldStyle(.roundedBorder)

            Text("Detected channel: \(appState.effectiveMyChannelName)")
                .font(.caption)
                .foregroundStyle(Color.black.opacity(0.52))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Title A")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.76))
                    TextField("Enter title for Thumbnail A", text: $appState.myTitleA)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Title B")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.76))
                    TextField("Enter title for Thumbnail B", text: $appState.myTitleB)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08), lineWidth: 1))
    }

    private var handlesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Competitor Handles")
                .font(.headline)
                .foregroundStyle(Color.black.opacity(0.85))

            Text("Add multiple handles with comma, space, or newline separators")
                .font(.caption)
                .foregroundStyle(Color.black.opacity(0.54))

            TextEditor(text: $appState.competitorHandlesInput)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .frame(height: 110)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.12), lineWidth: 1))

            HStack {
                Text("Latest videos per channel: \(appState.latestCount)")
                    .foregroundStyle(Color.black.opacity(0.8))
                Stepper("", value: $appState.latestCount, in: 3...30)
                    .labelsHidden()
                Spacer()
                Text("16:9 YouTube layout • Shorts filtered")
                    .font(.caption)
                    .foregroundStyle(Color.black.opacity(0.45))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08), lineWidth: 1))
    }

    private var actionBar: some View {
        HStack {
            Button {
                Task { await appState.fetchCompetitors() }
            } label: {
                HStack(spacing: 8) {
                    if appState.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(appState.isLoading ? "Fetching..." : "Fetch Competitors")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 1.0, green: 0.0, blue: 0.0).opacity(appState.myThumbnailA == nil || appState.isLoading ? 0.45 : 0.9))
            )
            .disabled(appState.myThumbnailA == nil || appState.isLoading)

            Spacer()
        }
    }
}
