// Covers and pages: fetched once, kept on disk, decoded off the main thread, and held in memory
// while they're on screen. Most of the disk copy is a cache iOS may clear; covers for the library
// are also kept where it won't.

import CryptoKit
import ImageIO
import SwiftUI

final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()

    private final class Box {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private let memory = NSCache<NSString, Box>()
    private let folder: URL
    private let kept = Storage.folder("covers")
    private let lock = NSLock()
    private var running: [String: Task<CGImage, Error>] = [:]

    private init() {
        memory.totalCostLimit = 256 << 20
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func key(_ url: URL, _ maxPixel: Int?, _ crop: Crop = .none) -> String {
        url.absoluteString + "#" + (maxPixel.map(String.init) ?? "full") + (crop == .none ? "" : "#\(crop)")
    }

    /// Named by path, not host, so nothing is lost if the server moves to another address.
    private func name(for url: URL) -> String {
        let digest = SHA256.hash(data: Data((url.path + "?" + (url.query ?? "")).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func file(for url: URL) -> URL {
        folder.appendingPathComponent(name(for: url))
    }

    /// Already decoded and in memory, so a cell can show it on its first frame.
    func cached(_ url: URL, maxPixel: Int?, crop: Crop = .none) -> CGImage? {
        memory.object(forKey: key(url, maxPixel, crop) as NSString)?.image
    }

    func image(_ url: URL, maxPixel: Int?, crop: Crop = .none) async throws -> CGImage {
        let key = key(url, maxPixel, crop)
        if let hit = memory.object(forKey: key as NSString) { return hit.image }

        let task: Task<CGImage, Error> = lock.withLock {
            if let existing = running[key] { return existing }
            let task = Task<CGImage, Error>.detached(priority: .userInitiated) { [self] in
                let data = try await self.data(url)
                guard var image = Self.decode(data, maxPixel: maxPixel) else {
                    try? FileManager.default.removeItem(at: self.file(for: url))
                    throw APIError(message: "That image couldn't be read")
                }
                if crop != .none { image = Self.trimmed(image, sidesOnly: crop == .sides) }
                self.memory.setObject(Box(image), forKey: key as NSString, cost: image.bytesPerRow * image.height)
                return image
            }
            running[key] = task
            return task
        }
        defer { lock.withLock { running[key] = nil } }
        return try await task.value
    }

    /// Fetches into the disk cache without decoding, for the pages just ahead in the reader.
    func warm(_ url: URL) {
        guard !url.isFileURL, !FileManager.default.fileExists(atPath: file(for: url).path) else { return }
        Task.detached(priority: .utility) { [self] in _ = try? await self.data(url) }
    }

    /// Copies an image into permanent storage, fetching it first if need be.
    func keep(_ url: URL) async {
        let target = kept.appendingPathComponent(name(for: url))
        guard !url.isFileURL, !FileManager.default.fileExists(atPath: target.path) else { return }
        if let data = try? await data(url) { try? data.write(to: target, options: .atomic) }
    }

    private func data(_ url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        if let data = try? Data(contentsOf: kept.appendingPathComponent(name(for: url))), !data.isEmpty { return data }
        let file = file(for: url)
        if let data = try? Data(contentsOf: file), !data.isEmpty { return data }
        let (data, response) = try await GQL.session.data(for: Server.shared.request(url))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError(message: "The server answered \(http.statusCode)")
        }
        try? data.write(to: file, options: .atomic)
        return data
    }

    private static func decode(_ data: Data, maxPixel: Int?) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        if let maxPixel {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    // MARK: Cropping borders

    enum Crop {
        /// As decoded.
        case none
        /// The blank margin on all four sides, for a page shown alone.
        case all
        /// Left and right only, for strips whose slices have to keep meeting top to bottom.
        case sides
    }

    /// Cuts away a plain white or black margin. Looks at a small grey copy to find where the
    /// artwork starts, and leaves the image alone if it has no such margin.
    static func trimmed(_ image: CGImage, sidesOnly: Bool) -> CGImage {
        let scale = min(1, 320 / CGFloat(max(image.width, image.height)))
        let width = max(Int(CGFloat(image.width) * scale), 1)
        let height = max(Int(CGFloat(image.height) * scale), 1)
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, width > 8, height > 8 else { return image }

        let corners = [pixels[0], pixels[width - 1], pixels[(height - 1) * width], pixels[height * width - 1]].sorted()
        let border = Int(corners[1]) / 2 + Int(corners[2]) / 2
        guard border > 232 || border < 24 else { return image }

        func marked(_ x: Int, _ y: Int) -> Bool { abs(Int(pixels[y * width + x]) - border) > 40 }
        // A line counts as artwork once more than a speck of it differs from the margin.
        func row(_ y: Int) -> Bool { (0..<width).reduce(0) { $0 + (marked($1, y) ? 1 : 0) } > max(width / 200, 1) }
        func column(_ x: Int) -> Bool { (0..<height).reduce(0) { $0 + (marked(x, $1) ? 1 : 0) } > max(height / 200, 1) }

        guard let left = (0..<width).first(where: column), let right = (0..<width).last(where: column) else { return image }
        var top = 0
        var bottom = height - 1
        if !sidesOnly {
            guard let first = (0..<height).first(where: row), let last = (0..<height).last(where: row) else { return image }
            top = first
            bottom = last
        }

        let rect = CGRect(x: CGFloat(left) / scale - 2, y: CGFloat(top) / scale - 2,
                          width: CGFloat(right - left + 1) / scale + 4, height: CGFloat(bottom - top + 1) / scale + 4)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)).integral
        let kept = (rect.width * rect.height) / CGFloat(image.width * image.height)
        guard kept < 0.98, rect.width > CGFloat(image.width) * 0.3, rect.height > CGFloat(image.height) * 0.3 else { return image }
        return image.cropping(to: rect) ?? image
    }

    // MARK: Housekeeping

    func diskBytes() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// A cover that changed on the server keeps its address, so drop ours.
    func forget(_ url: URL) {
        try? FileManager.default.removeItem(at: file(for: url))
        try? FileManager.default.removeItem(at: kept.appendingPathComponent(name(for: url)))
        for size in Cover.sizes { memory.removeObject(forKey: key(url, size) as NSString) }
    }
}

/// A server image, filling whatever frame it's given.
struct RemoteImage: View {
    let path: String?
    var maxPixel: Int? = Cover.grid

    @State private var loaded: CGImage?
    @State private var loadedPath: String?

    var body: some View {
        let url = Server.shared.url(path)
        let image = (loadedPath == path ? loaded : nil) ?? url.flatMap { ImageStore.shared.cached($0, maxPixel: maxPixel) }
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            }
        }
        .task(id: path) {
            guard let url, image == nil else { return }
            loaded = try? await ImageStore.shared.image(url, maxPixel: maxPixel)
            loadedPath = path
        }
    }
}

enum Cover {
    static let grid = 480
    static let large = 900
    static let icon = 144
    static let sizes = [grid, large, icon]
}

/// A cover at manga proportions.
struct CoverView: View {
    let path: String?
    var maxPixel: Int = Cover.grid
    var radius: CGFloat = 10

    var body: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay { RemoteImage(path: path, maxPixel: maxPixel) }
            .clipShape(.rect(cornerRadius: radius))
    }
}

/// A source or extension icon.
struct IconView: View {
    let path: String?
    var size: CGFloat = 40

    var body: some View {
        RemoteImage(path: path, maxPixel: Cover.icon)
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.24))
    }
}
