import Foundation
import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var myThumbnailA: NSImage?
    @Published var myThumbnailB: NSImage?
    @Published var myChannelInput: String = ""
    @Published var myChannelAvatarURL: URL?
    @Published var myChannelName: String = "Your Channel"
    @Published var myTitleA: String = "My Video Title"
    @Published var myTitleB: String = "My Alternate Video Title"
    @Published var selectedVariant: ThumbnailVariant = .a

    @Published var competitorHandlesInput: String = ""
    @Published var latestCount: Int = 12
    @Published var competitors: [CompetitorChannel] = []

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var fetchLogs: [String] = []
    @Published var currentScreen: Screen = .setup

    @Published var apiKey: String = ""
    @Published var useSearchFallback: Bool = false

    private let apiService = YouTubeAPIService()

    enum Screen {
        case setup
        case compare
    }

    init() {
        apiKey = KeychainStore.load(account: "youtube_api_key") ?? ""
        if let fallbackFlag = KeychainStore.load(account: "use_search_fallback") {
            useSearchFallback = (fallbackFlag == "1")
        }
    }

    var parsedHandles: [String] {
        competitorHandlesInput
            .components(separatedBy: CharacterSet(charactersIn: ", \n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.hasPrefix("@") ? String($0.dropFirst()) : $0 }
    }

    var hasFetchedData: Bool {
        !competitors.isEmpty
    }

    var currentThumbnail: NSImage? {
        switch selectedVariant {
        case .a: return myThumbnailA
        case .b: return myThumbnailB ?? myThumbnailA
        }
    }

    var currentMyTitle: String {
        switch selectedVariant {
        case .a:
            return myTitleA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My Video Title" : myTitleA
        case .b:
            let value = myTitleB.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? "My Alternate Video Title" : value
        }
    }

    var effectiveMyChannelName: String {
        let value = myChannelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Your Channel" : value
    }

    var canToggleAB: Bool {
        myThumbnailA != nil && myThumbnailB != nil
    }

    func saveSettings() {
        _ = KeychainStore.save(value: apiKey, account: "youtube_api_key")
        _ = KeychainStore.save(value: useSearchFallback ? "1" : "0", account: "use_search_fallback")
    }

    func fetchCompetitors() async {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Missing API key. Open Settings and add your YouTube Data API key."
            return
        }

        let handles = parsedHandles
        guard !handles.isEmpty else {
            errorMessage = "Add at least one competitor handle (example: @somechannel)."
            return
        }

        isLoading = true
        errorMessage = nil
        fetchLogs = []

        if !myChannelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let profile = await apiService.fetchChannelProfile(
                input: myChannelInput,
                apiKey: apiKey,
                useSearchFallback: useSearchFallback
            ) {
                myChannelName = profile.title
                myChannelAvatarURL = profile.avatarURL
            }
        }

        let fetched = await apiService.fetchCompetitors(
            handles: handles,
            latestCount: latestCount,
            apiKey: apiKey,
            useSearchFallback: useSearchFallback
        )

        competitors = fetched
        isLoading = false

        fetchLogs = fetched.map { channel in
            if let error = channel.errorMessage {
                return "\(channel.handle): FAILED - \(error)"
            }
            return "\(channel.handle): OK (\(channel.videos.count) videos)"
        }

        if fetched.allSatisfy({ $0.errorMessage != nil }) {
            let details = fetched.compactMap(\.errorMessage).first ?? "Unknown fetch error"
            errorMessage = "All competitor fetches failed: \(details)"
            currentScreen = .setup
            return
        }

        currentScreen = .compare
    }
}
