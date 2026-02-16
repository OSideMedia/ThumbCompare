import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CompareView: View {
    @EnvironmentObject private var appState: AppState
    @State private var exportStatusMessage: String?

    struct FeedEntry: Identifiable {
        let id: String
        let video: VideoItem
        let channelTitle: String
        let channelAvatarURL: URL?
        let isVerified: Bool
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 360, maximum: 460), spacing: 20, alignment: .top)]
    }

    private var competitorEntries: [FeedEntry] {
        let channels = appState.competitors.filter { $0.errorMessage == nil }
        var buckets: [[FeedEntry]] = channels.map { channel in
            channel.videos.map { video in
                FeedEntry(
                    id: "\(channel.id)_\(video.id)",
                    video: video,
                    channelTitle: channel.title,
                    channelAvatarURL: channel.avatarURL,
                    isVerified: channel.isVerified
                )
            }
        }

        var mixed: [FeedEntry] = []
        var didAppend = true
        while didAppend {
            didAppend = false
            for idx in buckets.indices {
                if !buckets[idx].isEmpty {
                    mixed.append(buckets[idx].removeFirst())
                    didAppend = true
                }
            }
        }
        return mixed
    }

    private var failedChannels: [CompetitorChannel] {
        appState.competitors.filter { $0.errorMessage != nil }
    }

    var body: some View {
        VStack(spacing: 14) {
            topBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !failedChannels.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Failed Handles")
                                .font(.headline)
                            ForEach(failedChannels) { channel in
                                Text("\(channel.handle): \(channel.errorMessage ?? "Unknown error")")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
                    }

                    LazyVGrid(columns: gridColumns, spacing: 20) {
                        FeedCard(
                            title: appState.currentMyTitle,
                            channelName: appState.effectiveMyChannelName,
                            isVerified: false,
                            subtitle: "622 views • 1 hour ago",
                            imageURL: nil,
                            imageNS: appState.currentThumbnail,
                            avatarURL: appState.myChannelAvatarURL
                        )

                        ForEach(competitorEntries) { entry in
                            FeedCard(
                                title: entry.video.title,
                                channelName: entry.channelTitle,
                                isVerified: entry.isVerified,
                                subtitle: videoStatsLine(entry.video),
                                imageURL: entry.video.bestThumbnailURL()?.url,
                                imageNS: nil,
                                avatarURL: entry.channelAvatarURL
                            )
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            if let message = exportStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.black.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
    }

    private var topBar: some View {
            HStack(spacing: 14) {
            Text("YouTube Feed Compare (16:9)")
                .font(.headline)

            if appState.canToggleAB {
                Picker("Thumbnail", selection: $appState.selectedVariant) {
                    Text("A").tag(ThumbnailVariant.a)
                    Text("B").tag(ThumbnailVariant.b)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            Button("Refresh") {
                Task { await appState.fetchCompetitors() }
            }
            .disabled(appState.isLoading)

            Button("Export PNG") {
                Task { @MainActor in
                    exportCurrentCompareSnapshot()
                }
            }

            Button("Back to Setup") {
                appState.currentScreen = .setup
            }

            Spacer()

            if appState.isLoading {
                ProgressView()
            }
        }
    }

    private func videoStatsLine(_ video: VideoItem) -> String {
        var parts: [String] = []
        if let count = video.viewCount {
            parts.append(Self.compactViews(count))
        }
        if let publishedAt = video.publishedAt {
            parts.append(Self.relativeTime(from: publishedAt))
        }
        return parts.isEmpty ? "" : parts.joined(separator: " • ")
    }

    private static func compactViews(_ value: Int) -> String {
        if value >= 1_000_000_000 { return String(format: "%.1fB views", Double(value) / 1_000_000_000).replacingOccurrences(of: ".0", with: "") }
        if value >= 1_000_000 { return String(format: "%.1fM views", Double(value) / 1_000_000).replacingOccurrences(of: ".0", with: "") }
        if value >= 1_000 { return String(format: "%.1fK views", Double(value) / 1_000).replacingOccurrences(of: ".0", with: "") }
        return "\(value) views"
    }

    private static func relativeTime(from date: Date) -> String {
        let delta = max(1, Int(Date().timeIntervalSince(date)))
        let day = 86400
        let hour = 3600
        if delta >= day {
            let d = delta / day
            return d == 1 ? "1 day ago" : "\(d) days ago"
        }
        let h = max(1, delta / hour)
        return h == 1 ? "1 hour ago" : "\(h) hours ago"
    }

    @MainActor
    private func exportCurrentCompareSnapshot() {
        let filename = "ThumbCompare-\(Self.timestampForFilename()).png"
        let exportsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThumbCompareExports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: exportsDir, withIntermediateDirectories: true)
        } catch {
            exportStatusMessage = "Export failed: \(error.localizedDescription)"
            return
        }
        let url = exportsDir.appendingPathComponent(filename)

        let exportView = CompareExportSnapshotView(
            appState: appState,
            competitorEntries: competitorEntries,
            failedChannels: failedChannels,
            videoStatsLine: videoStatsLine
        )

        let renderer = ImageRenderer(content: exportView)
        renderer.scale = 2.0
        renderer.proposedSize = .init(width: 1600, height: nil)

        guard let nsImage = renderer.nsImage,
              let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            exportStatusMessage = "Export failed: could not render PNG."
            return
        }

        do {
            try pngData.write(to: url, options: .atomic)
            exportStatusMessage = "Exported PNG to \(url.path)"
        } catch {
            exportStatusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private static func timestampForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }
}

private struct CompareExportSnapshotView: View {
    let appState: AppState
    let competitorEntries: [CompareView.FeedEntry]
    let failedChannels: [CompetitorChannel]
    let videoStatsLine: (VideoItem) -> String

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 360, maximum: 460), spacing: 16, alignment: .top)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ThumbCompare Export")
                .font(.title2.weight(.bold))

            if !failedChannels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Failed Handles")
                        .font(.headline)
                    ForEach(failedChannels) { channel in
                        Text("\(channel.handle): \(channel.errorMessage ?? "Unknown error")")
                            .font(.caption.monospaced())
                            .foregroundStyle(.red)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
            }

            LazyVGrid(columns: gridColumns, spacing: 16) {
                FeedCard(
                    title: appState.currentMyTitle,
                    channelName: appState.effectiveMyChannelName,
                    isVerified: false,
                    subtitle: "622 views • 1 hour ago",
                    imageURL: nil,
                    imageNS: appState.currentThumbnail,
                    avatarURL: appState.myChannelAvatarURL
                )

                ForEach(competitorEntries) { entry in
                    FeedCard(
                        title: entry.video.title,
                        channelName: entry.channelTitle,
                        isVerified: entry.isVerified,
                        subtitle: videoStatsLine(entry.video),
                        imageURL: entry.video.bestThumbnailURL()?.url,
                        imageNS: nil,
                        avatarURL: entry.channelAvatarURL
                    )
                }
            }
        }
        .padding(20)
        .frame(width: 1600, alignment: .topLeading)
        .background(Color.white)
    }
}

private struct FeedCard: View {
    let title: String
    let channelName: String
    let isVerified: Bool
    let subtitle: String
    let imageURL: URL?
    let imageNS: NSImage?
    let avatarURL: URL?

    @State private var image: NSImage?
    @State private var avatar: NSImage?
    @State private var loadingImage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.08))

                if let image = image ?? imageNS {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else if loadingImage {
                    ProgressView()
                } else {
                    Text("No Thumbnail")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(alignment: .top, spacing: 10) {
                avatarView

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)

                    HStack(spacing: 4) {
                        Text(channelName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .task(id: imageURL?.absoluteString ?? "no-image") {
            guard let imageURL else { return }
            loadingImage = true
            image = await ImageLoader.shared.load(videoId: nil, quality: "feed", from: imageURL)
            loadingImage = false
        }
        .task(id: avatarURL?.absoluteString ?? "no-avatar") {
            guard let avatarURL else { return }
            avatar = await ImageLoader.shared.load(videoId: nil, quality: "avatar", from: avatarURL)
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatar {
            Image(nsImage: avatar)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.gray.opacity(0.35))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                )
        }
    }
}
