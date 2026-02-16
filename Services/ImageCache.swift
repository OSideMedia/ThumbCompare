import Foundation
import AppKit

actor ImageCache {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let cacheURL: URL

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = base.appendingPathComponent("ThumbCompare", isDirectory: true)
        let cacheFolder = appFolder.appendingPathComponent("Cache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        self.cacheURL = cacheFolder
    }

    private func diskURL(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return cacheURL.appendingPathComponent(safe).appendingPathExtension("bin")
    }

    func image(forKey key: String) -> NSImage? {
        if let image = memoryCache.object(forKey: key as NSString) {
            return image
        }

        let path = diskURL(for: key)
        guard let data = try? Data(contentsOf: path),
              let image = NSImage(data: data) else {
            return nil
        }

        memoryCache.setObject(image, forKey: key as NSString)
        return image
    }

    func store(_ image: NSImage, data: Data, forKey key: String) {
        memoryCache.setObject(image, forKey: key as NSString)
        try? data.write(to: diskURL(for: key), options: .atomic)
    }
}

actor ImageLoader {
    static let shared = ImageLoader()

    func load(videoId: String?, quality: String, from url: URL) async -> NSImage? {
        let cacheKey = "\(videoId ?? url.absoluteString)_\(quality)"
        if let cached = await ImageCache.shared.image(forKey: cacheKey) {
            return cached
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = NSImage(data: data) else { return nil }
            await ImageCache.shared.store(image, data: data, forKey: cacheKey)
            return image
        } catch {
            return nil
        }
    }
}
