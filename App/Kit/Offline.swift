// What the phone keeps so the app works with no server: the last good copy of each list, and
// reading progress that hasn't reached the server yet. All of it lives in Application Support,
// which iOS never clears on its own and which survives installing a new build over the old one.

import Foundation

enum Storage {
    /// Application Support/Yomu. Gone only if the app itself is deleted from the phone.
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Yomu", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func folder(_ name: String, backedUp: Bool = true) -> URL {
        var url = root.appendingPathComponent(name, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            if !backedUp {
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? url.setResourceValues(values)
            }
        }
        return url
    }

    static func bytes(in folder: URL) -> Int {
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let file as URL in files {
            total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }
}

/// Whether the server answers, asked at most every few seconds so an unreachable server costs
/// one short wait instead of a full timeout on every call.
final class Reach: @unchecked Sendable {
    static let shared = Reach()

    private let lock = NSLock()
    private var known: (at: Date, online: Bool)?
    private var probing: Task<Bool, Never>?

    func mark(_ online: Bool) {
        lock.withLock { known = (.now, online) }
    }

    /// The address changed, so what was known about the old one no longer applies.
    func forget() {
        lock.withLock { known = nil }
    }

    func online() async -> Bool {
        let task: Task<Bool, Never> = lock.withLock {
            if let known, Date.now.timeIntervalSince(known.at) < 8 { return Task { known.online } }
            if let probing { return probing }
            let task = Task<Bool, Never> { [self] in
                let result = await probe()
                lock.withLock {
                    known = (.now, result)
                    probing = nil
                }
                return result
            }
            probing = task
            return task
        }
        return await task.value
    }

    private func probe() async -> Bool {
        guard let base = Server.shared.base else { return false }
        var request = Server.shared.request(base.appendingPathComponent("api/v1/settings/about"))
        request.timeoutInterval = 2.5
        guard let (_, response) = try? await GQL.session.data(for: request) else { return false }
        return (response as? HTTPURLResponse) != nil
    }
}

enum Offline {
    private static let folder = Storage.folder("snapshots")
    private static let lock = NSLock()
    private static var library: Set<Int>?

    private static func file(_ name: String) -> URL {
        folder.appendingPathComponent(name + ".json")
    }

    static func read<T: Decodable>(_ name: String, as type: T.Type = T.self) -> T? {
        guard let data = try? Data(contentsOf: file(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func write<T: Encodable>(_ name: String, _ value: T) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: file(name), options: .atomic)
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: file(name))
    }

    /// Runs `fetch` and remembers what it returned. With no server, hands back what was
    /// remembered last time. `fresh` says which of the two happened.
    static func cached<T: Codable>(_ name: String, save: (T) -> Bool = { _ in true },
                                   _ fetch: () async throws -> T) async throws -> (value: T, fresh: Bool) {
        if !(await Reach.shared.online()), let kept: T = read(name) { return (kept, false) }
        do {
            let value = try await fetch()
            if save(value) { write(name, value) }
            return (value, true)
        } catch let error as URLError {
            if let kept: T = read(name) { return (kept, false) }
            throw error
        }
    }

    /// Brings every remembered list up to date, so a tab that was never opened still has
    /// something to show with no server.
    static func refresh() async {
        guard await Reach.shared.online() else { return }
        _ = try? await API.library()
        _ = try? await API.categories()
        _ = try? await API.updates()
        _ = try? await API.history()
        _ = try? await API.sources()
    }

    // MARK: Which series are worth keeping

    static var libraryIDs: Set<Int> {
        get {
            lock.withLock {
                if library == nil { library = Set((read("library", as: [Manga].self) ?? []).map(\.id)) }
                return library ?? []
            }
        }
        set { lock.withLock { library = newValue } }
    }

    /// Details and chapter lists are kept for the library and for anything with chapters saved.
    static func keeps(_ manga: Int) -> Bool {
        libraryIDs.contains(manga) || Downloads.shared.count(manga: manga) > 0 || Downloads.shared.isQueued(manga: manga)
    }

    /// Saves a series' details, chapter list and cover now, for when it's opened with no server.
    static func keep(manga id: Int) async {
        guard let manga = try? await API.manga(id), (try? await API.chapters(of: id)) != nil else { return }
        if let url = Server.shared.url(manga.thumbnailUrl) { await ImageStore.shared.keep(url) }
    }

    static func forget(manga id: Int) {
        guard !keeps(id) else { return }
        remove("manga-\(id)")
        remove("chapters-\(id)")
    }
}

/// Read marks, bookmarks and page positions made on the phone. Each is written here first and
/// sent to the server when it can be reached, so reading with no server loses nothing.
final class Marks: @unchecked Sendable {
    static let shared = Marks()

    struct Patch: Codable, Hashable {
        var read: Bool?
        var bookmarked: Bool?
        var lastPage: Int?
        var synced = false
    }

    private let lock = NSLock()
    private var patches: [Int: Patch]
    private var sending = false

    private init() {
        patches = Offline.read("marks", as: [Int: Patch].self) ?? [:]
    }

    private func save() {
        Offline.write("marks", lock.withLock { patches })
    }

    var unsent: Int {
        lock.withLock { patches.values.filter { !$0.synced }.count }
    }

    func record(_ ids: [Int], read: Bool?, bookmarked: Bool?, lastPage: Int?) {
        lock.withLock {
            for id in ids {
                var patch = patches[id] ?? Patch()
                if let read { patch.read = read }
                if let bookmarked { patch.bookmarked = bookmarked }
                if let lastPage { patch.lastPage = lastPage }
                patch.synced = false
                patches[id] = patch
            }
        }
        save()
    }

    /// Sends everything the server hasn't had. Safe to call often; does nothing with no server.
    func sync() async {
        let waiting: [Int: Patch] = lock.withLock {
            guard !sending else { return [:] }
            let waiting = patches.filter { !$0.value.synced }
            sending = !waiting.isEmpty
            return waiting
        }
        guard !waiting.isEmpty else { return }
        defer { lock.withLock { sending = false } }
        guard await Reach.shared.online() else { return }

        for (patch, entries) in Dictionary(grouping: waiting, by: \.value) {
            let ids = entries.map(\.key)
            do {
                try await API.send(chapters: ids, read: patch.read, bookmarked: patch.bookmarked, lastPage: patch.lastPage)
            } catch {
                continue
            }
            lock.withLock {
                // Leave alone anything that changed again while this was in flight.
                for id in ids where patches[id] == patch { patches[id]?.synced = true }
            }
        }
        save()
    }

    /// Lays the phone's marks over a chapter list. A fresh list from the server already has
    /// everything that was sent, so those entries are dropped; a remembered list has none of it.
    func apply(to chapters: inout [Chapter], fresh: Bool) {
        var dropped = false
        lock.withLock {
            guard !patches.isEmpty else { return }
            for index in chapters.indices {
                guard let patch = patches[chapters[index].id] else { continue }
                if fresh, patch.synced {
                    patches[chapters[index].id] = nil
                    dropped = true
                    continue
                }
                if let read = patch.read { chapters[index].isRead = read }
                if let bookmarked = patch.bookmarked { chapters[index].isBookmarked = bookmarked }
                if let lastPage = patch.lastPage { chapters[index].lastPageRead = lastPage }
            }
        }
        if dropped { save() }
    }
}
