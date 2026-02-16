import Foundation

enum YouTubeAPIError: LocalizedError {
    case invalidAPIKey
    case invalidHandle(String)
    case responseError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Missing API key. Set it in Settings before fetching competitors."
        case .invalidHandle(let handle):
            return "Could not resolve handle: @\(handle)"
        case .responseError(let msg), .networkError(let msg):
            return msg
        }
    }
}

struct YouTubeAPIService {
    // Fetch flow:
    // 1) Resolve handle with channels.list?forHandle
    // 2) Optional fallback via search.list (higher quota)
    // 3) Read uploads playlist from contentDetails.relatedPlaylists.uploads
    // 4) Fetch a recent window from playlistItems.list
    // 5) Use videos.list contentDetails.duration to filter out Shorts
    // 6) Keep N non-Shorts, landscape-friendly thumbnails for feed comparison
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private let apiHosts = ["www.googleapis.com", "youtube.googleapis.com"]

    func fetchChannelProfile(input: String, apiKey: String, useSearchFallback: Bool) async -> (title: String, avatarURL: URL?)? {
        do {
            let resolved = try await resolveChannelFromInput(input: input, apiKey: apiKey, useSearchFallback: useSearchFallback)
            return (resolved.channelTitle, resolved.avatarURL)
        } catch {
            return nil
        }
    }

    func fetchCompetitors(
        handles: [String],
        latestCount: Int,
        apiKey: String,
        useSearchFallback: Bool
    ) async -> [CompetitorChannel] {
        await withTaskGroup(of: CompetitorChannel.self) { group in
            for handle in handles {
                group.addTask {
                    await fetchChannel(for: handle, latestCount: latestCount, apiKey: apiKey, useSearchFallback: useSearchFallback)
                }
            }

            var result: [CompetitorChannel] = []
            for await channel in group {
                result.append(channel)
            }
            return result.sorted { $0.handle.localizedCaseInsensitiveCompare($1.handle) == .orderedAscending }
        }
    }

    private func fetchChannel(
        for inputHandle: String,
        latestCount: Int,
        apiKey: String,
        useSearchFallback: Bool
    ) async -> CompetitorChannel {
        let cleanHandle = inputHandle.replacingOccurrences(of: "@", with: "")
        do {
            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw YouTubeAPIError.invalidAPIKey
            }

            let channelContext = try await resolveChannel(handle: cleanHandle, apiKey: apiKey, useSearchFallback: useSearchFallback)
            let videos = try await fetchUploads(playlistId: channelContext.uploadsPlaylistId, maxResults: latestCount, apiKey: apiKey)

            return CompetitorChannel(
                id: channelContext.channelId,
                handle: "@\(cleanHandle)",
                title: channelContext.channelTitle,
                avatarURL: channelContext.avatarURL,
                isVerified: true,
                uploadsPlaylistId: channelContext.uploadsPlaylistId,
                videos: videos,
                errorMessage: nil,
                lastFetchedAt: Date()
            )
        } catch {
            return CompetitorChannel(
                id: "error_\(cleanHandle)",
                handle: "@\(cleanHandle)",
                title: "Unknown Channel",
                avatarURL: nil,
                isVerified: false,
                uploadsPlaylistId: nil,
                videos: [],
                errorMessage: error.localizedDescription,
                lastFetchedAt: nil
            )
        }
    }

    private func resolveChannel(handle: String, apiKey: String, useSearchFallback: Bool) async throws -> ResolvedChannel {
        let queryItems = [
            URLQueryItem(name: "part", value: "id,contentDetails,snippet"),
            URLQueryItem(name: "forHandle", value: handle),
            URLQueryItem(name: "key", value: apiKey)
        ]

        let (data, response) = try await apiRequest(path: "channels", queryItems: queryItems)
        try validate(response: response, data: data)
        let channelResponse = try decoder.decode(ChannelListResponse.self, from: data)

        if let first = channelResponse.items.first,
           let uploads = first.contentDetails.relatedPlaylists.uploads {
            return ResolvedChannel(
                channelId: first.id,
                channelTitle: first.snippet.title,
                avatarURL: first.snippet.bestAvatarURL,
                uploadsPlaylistId: uploads
            )
        }

        guard useSearchFallback else {
            throw YouTubeAPIError.invalidHandle(handle)
        }

        return try await fallbackResolveWithSearch(handle: handle, apiKey: apiKey)
    }

    private func resolveChannelFromInput(input: String, apiKey: String, useSearchFallback: Bool) async throws -> ResolvedChannel {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw YouTubeAPIError.invalidHandle(input)
        }

        if let channelID = extractChannelID(from: trimmed) {
            return try await resolveChannelByID(channelID: channelID, apiKey: apiKey)
        }

        let handle = extractHandle(from: trimmed) ?? trimmed.replacingOccurrences(of: "@", with: "")
        return try await resolveChannel(handle: handle, apiKey: apiKey, useSearchFallback: useSearchFallback)
    }

    private func resolveChannelByID(channelID: String, apiKey: String) async throws -> ResolvedChannel {
        let channelQueryItems = [
            URLQueryItem(name: "part", value: "id,contentDetails,snippet"),
            URLQueryItem(name: "id", value: channelID),
            URLQueryItem(name: "key", value: apiKey)
        ]

        let (channelData, channelResponse) = try await apiRequest(path: "channels", queryItems: channelQueryItems)
        try validate(response: channelResponse, data: channelData)
        let channelList = try decoder.decode(ChannelListResponse.self, from: channelData)

        guard let first = channelList.items.first,
              let uploads = first.contentDetails.relatedPlaylists.uploads else {
            throw YouTubeAPIError.invalidHandle(channelID)
        }

        return ResolvedChannel(
            channelId: first.id,
            channelTitle: first.snippet.title,
            avatarURL: first.snippet.bestAvatarURL,
            uploadsPlaylistId: uploads
        )
    }

    private func fallbackResolveWithSearch(handle: String, apiKey: String) async throws -> ResolvedChannel {
        let searchQueryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "q", value: handle),
            URLQueryItem(name: "type", value: "channel"),
            URLQueryItem(name: "maxResults", value: "1"),
            URLQueryItem(name: "key", value: apiKey)
        ]

        let (searchData, searchResponse) = try await apiRequest(path: "search", queryItems: searchQueryItems)
        try validate(response: searchResponse, data: searchData)
        let decodedSearch = try decoder.decode(SearchResponse.self, from: searchData)

        guard let channelId = decodedSearch.items.first?.id.channelId else {
            throw YouTubeAPIError.invalidHandle(handle)
        }

        let channelQueryItems = [
            URLQueryItem(name: "part", value: "id,contentDetails,snippet"),
            URLQueryItem(name: "id", value: channelId),
            URLQueryItem(name: "key", value: apiKey)
        ]

        let (channelData, channelResponse) = try await apiRequest(path: "channels", queryItems: channelQueryItems)
        try validate(response: channelResponse, data: channelData)
        let channelList = try decoder.decode(ChannelListResponse.self, from: channelData)

        guard let first = channelList.items.first,
              let uploads = first.contentDetails.relatedPlaylists.uploads else {
            throw YouTubeAPIError.invalidHandle(handle)
        }

        return ResolvedChannel(
            channelId: first.id,
            channelTitle: first.snippet.title,
            avatarURL: first.snippet.bestAvatarURL,
            uploadsPlaylistId: uploads
        )
    }

    private func fetchUploads(playlistId: String, maxResults: Int, apiKey: String) async throws -> [VideoItem] {
        let expandedFetchCount = min(50, max(maxResults * 3, maxResults + 10))
        let queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "playlistId", value: playlistId),
            URLQueryItem(name: "maxResults", value: "\(expandedFetchCount)"),
            URLQueryItem(name: "key", value: apiKey)
        ]

        let (data, response) = try await apiRequest(path: "playlistItems", queryItems: queryItems)
        try validate(response: response, data: data)
        let decoded = try decoder.decode(PlaylistItemsResponse.self, from: data)

        let sourceItems: [VideoItem] = decoded.items.compactMap { item in
            let parsedDate: Date?
            if let publishedAt = item.snippet.publishedAt {
                parsedDate = ISO8601DateFormatter().date(from: publishedAt)
            } else {
                parsedDate = nil
            }

            let map = item.snippet.thumbnails.reduce(into: [String: ThumbnailCandidate]()) { acc, pair in
                if let url = URL(string: pair.value.url) {
                    acc[pair.key] = ThumbnailCandidate(
                        url: url,
                        width: pair.value.width,
                        height: pair.value.height
                    )
                }
            }

            return VideoItem(
                videoId: item.snippet.resourceId.videoId,
                title: item.snippet.title,
                publishedAt: parsedDate,
                viewCount: nil,
                thumbnails: map
            )
        }

        let videoIDs = sourceItems.compactMap(\.videoId)
        let details = try await fetchVideoDetails(videoIDs: videoIDs, apiKey: apiKey)

        let enriched = sourceItems.map { item -> VideoItem in
            guard let id = item.videoId, let detail = details[id] else { return item }
            return VideoItem(
                videoId: item.videoId,
                title: item.title,
                publishedAt: item.publishedAt,
                viewCount: detail.viewCount,
                thumbnails: item.thumbnails
            )
        }

        let filtered = enriched.filter { item in
            let isShortByDuration: Bool
            if let id = item.videoId, let secs = details[id]?.durationSeconds {
                isShortByDuration = secs <= 180
            } else {
                isShortByDuration = false
            }

            if isShortByDuration { return false }
            if item.title.localizedCaseInsensitiveContains("#shorts") { return false }
            return item.hasAny16x9LikeThumbnail || item.hasAnyLandscapeThumbnail
        }

        return Array(filtered.prefix(maxResults))
    }

    private func fetchVideoDetails(videoIDs: [String], apiKey: String) async throws -> [String: VideoDetails] {
        guard !videoIDs.isEmpty else { return [:] }

        var map: [String: VideoDetails] = [:]
        let chunks = stride(from: 0, to: videoIDs.count, by: 50).map { start in
            Array(videoIDs[start..<min(start + 50, videoIDs.count)])
        }

        for chunk in chunks {
            let queryItems = [
                URLQueryItem(name: "part", value: "contentDetails,statistics"),
                URLQueryItem(name: "id", value: chunk.joined(separator: ",")),
                URLQueryItem(name: "maxResults", value: "50"),
                URLQueryItem(name: "key", value: apiKey)
            ]

            let (data, response) = try await apiRequest(path: "videos", queryItems: queryItems)
            try validate(response: response, data: data)
            let decoded = try decoder.decode(VideosListResponse.self, from: data)

            for item in decoded.items {
                if let seconds = parseISODurationToSeconds(item.contentDetails.duration) {
                    map[item.id] = VideoDetails(
                        durationSeconds: seconds,
                        viewCount: Int(item.statistics?.viewCount ?? "")
                    )
                }
            }
        }

        return map
    }

    private func parseISODurationToSeconds(_ isoDuration: String) -> Int? {
        var value = isoDuration
        guard value.hasPrefix("PT") else { return nil }
        value.removeFirst(2)

        var number = ""
        var hours = 0
        var minutes = 0
        var seconds = 0

        for ch in value {
            if ch.isNumber {
                number.append(ch)
                continue
            }

            guard let n = Int(number) else { return nil }
            switch ch {
            case "H": hours = n
            case "M": minutes = n
            case "S": seconds = n
            default: return nil
            }
            number = ""
        }

        return (hours * 3600) + (minutes * 60) + seconds
    }

    private func extractHandle(from input: String) -> String? {
        if input.hasPrefix("@") {
            return String(input.dropFirst())
        }

        if let url = URL(string: input), let host = url.host?.lowercased(),
           host.contains("youtube.com") || host.contains("youtu.be") {
            let path = url.path
            if let atRange = path.range(of: "/@") {
                let suffix = path[atRange.upperBound...]
                let handle = suffix.split(separator: "/").first.map(String.init)
                return handle?.replacingOccurrences(of: "@", with: "")
            }
        }
        return nil
    }

    private func extractChannelID(from input: String) -> String? {
        if let url = URL(string: input), let host = url.host?.lowercased(),
           host.contains("youtube.com") || host.contains("youtu.be") {
            let parts = url.path.split(separator: "/").map(String.init)
            if parts.count >= 2 && parts[0] == "channel" {
                return parts[1]
            }
        }
        return nil
    }

    private func apiRequest(path: String, queryItems: [URLQueryItem]) async throws -> (Data, URLResponse) {
        var lastError: Error?

        for host in apiHosts {
            var components = URLComponents()
            components.scheme = "https"
            components.host = host
            components.path = "/youtube/v3/\(path)"
            components.queryItems = queryItems

            guard let url = components.url else { continue }

            do {
                return try await URLSession.shared.data(from: url)
            } catch {
                lastError = error
                if let urlError = error as? URLError, urlError.code == .cannotFindHost {
                    continue
                }
                throw error
            }
        }

        if let urlError = lastError as? URLError {
            throw YouTubeAPIError.networkError("Network error (\(urlError.code.rawValue)): \(urlError.localizedDescription)")
        }
        throw lastError ?? YouTubeAPIError.networkError("Unknown networking error")
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw YouTubeAPIError.networkError("Invalid response from YouTube API")
        }

        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw YouTubeAPIError.responseError("YouTube API error (\(http.statusCode)): \(message)")
        }
    }
}

private struct ResolvedChannel {
    let channelId: String
    let channelTitle: String
    let avatarURL: URL?
    let uploadsPlaylistId: String
}

private struct ChannelListResponse: Decodable {
    let items: [ChannelItem]
}

private struct ChannelItem: Decodable {
    let id: String
    let snippet: ChannelSnippet
    let contentDetails: ChannelContentDetails
}

private struct ChannelSnippet: Decodable {
    let title: String
    let thumbnails: [String: ThumbnailNode]?

    var bestAvatarURL: URL? {
        let preferred = ["high", "medium", "default"]
        for key in preferred {
            if let value = thumbnails?[key], let url = URL(string: value.url) {
                return url
            }
        }
        if let first = thumbnails?.first, let url = URL(string: first.value.url) {
            return url
        }
        return nil
    }
}

private struct ChannelContentDetails: Decodable {
    let relatedPlaylists: RelatedPlaylists
}

private struct RelatedPlaylists: Decodable {
    let uploads: String?
}

private struct PlaylistItemsResponse: Decodable {
    let items: [PlaylistItem]
}

private struct PlaylistItem: Decodable {
    let snippet: PlaylistSnippet
}

private struct PlaylistSnippet: Decodable {
    let title: String
    let publishedAt: String?
    let resourceId: ResourceId
    let thumbnails: [String: ThumbnailNode]
}

private struct ResourceId: Decodable {
    let videoId: String?
}

private struct ThumbnailNode: Decodable {
    let url: String
    let width: Int?
    let height: Int?
}

private struct SearchResponse: Decodable {
    let items: [SearchItem]
}

private struct SearchItem: Decodable {
    let id: SearchID
}

private struct SearchID: Decodable {
    let channelId: String?
}

private struct VideosListResponse: Decodable {
    let items: [VideoDurationItem]
}

private struct VideoDurationItem: Decodable {
    let id: String
    let contentDetails: VideoDurationDetails
    let statistics: VideoStatistics?
}

private struct VideoDurationDetails: Decodable {
    let duration: String
}

private struct VideoStatistics: Decodable {
    let viewCount: String?
}

private struct VideoDetails {
    let durationSeconds: Int
    let viewCount: Int?
}
