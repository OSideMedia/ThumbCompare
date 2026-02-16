import Foundation
import AppKit

enum ThumbnailVariant: String, CaseIterable {
    case a = "A"
    case b = "B"
}

struct ThumbnailCandidate: Hashable {
    let url: URL
    let width: Int?
    let height: Int?

    var isLandscape: Bool {
        guard let w = width, let h = height, h > 0 else { return true }
        return Double(w) / Double(h) > 1.2
    }

    var isYouTube16x9Like: Bool {
        guard let w = width, let h = height, h > 0 else { return true }
        let ratio = Double(w) / Double(h)
        return ratio >= 1.65 && ratio <= 1.95
    }
}

struct VideoItem: Identifiable, Hashable {
    let id: String
    let videoId: String?
    let title: String
    let publishedAt: Date?
    let viewCount: Int?
    let thumbnails: [String: ThumbnailCandidate]

    init(videoId: String?, title: String, publishedAt: Date?, viewCount: Int?, thumbnails: [String: ThumbnailCandidate]) {
        self.videoId = videoId
        self.title = title
        self.publishedAt = publishedAt
        self.viewCount = viewCount
        self.thumbnails = thumbnails
        self.id = videoId ?? UUID().uuidString
    }

    func bestThumbnailURL() -> (quality: String, url: URL)? {
        let preferred = ["maxres", "standard", "high", "medium", "default"]

        for quality in preferred {
            if let candidate = thumbnails[quality], candidate.isYouTube16x9Like {
                return (quality, candidate.url)
            }
        }

        for quality in preferred {
            if let candidate = thumbnails[quality], candidate.isLandscape {
                return (quality, candidate.url)
            }
        }

        for quality in preferred {
            if let candidate = thumbnails[quality] {
                return (quality, candidate.url)
            }
        }

        if let first = thumbnails.first {
            return (first.key, first.value.url)
        }
        return nil
    }

    var hasAnyLandscapeThumbnail: Bool {
        thumbnails.values.contains(where: { $0.isLandscape })
    }

    var hasAny16x9LikeThumbnail: Bool {
        thumbnails.values.contains(where: { $0.isYouTube16x9Like })
    }
}

struct CompetitorChannel: Identifiable, Hashable {
    let id: String
    let handle: String
    let title: String
    let avatarURL: URL?
    let isVerified: Bool
    let uploadsPlaylistId: String?
    var videos: [VideoItem]
    var errorMessage: String?
    var lastFetchedAt: Date?
}
