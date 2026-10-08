// Chapters saved on the phone. Pages are plain files under Application Support/Yomu/chapters,
// one folder per chapter, with an index beside them saying which chapters are complete.

import Foundation
import Observation

@Observable final class Downloads: @unchecked Sendable {
    static let shared = Downloads()

    struct Entry: Codable {
        var manga: Int
        var pages: Int
        var bytes: Int
    }

    struct Job: Identifiable, Hashable {
        let chapter: Int
        let manga: Int
        let title: String
        let name: String

        var id: Int { chapter }
    }

    private(set) var queue: [Job] = []
    private(set) var progress: [Int: Double] = [:]
    private(set) var problem: String?
    var paused = false {
        didSet { if !paused { run() } }
    }
    /// Goes up when the set of saved chapters changes, so views that asked `has` redraw.
    private var revision = 0

    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var index: [Int: Entry]
    @ObservationIgnored private var counts: [Int: Int] = [:]
    @ObservationIgnored private var queuedManga: [Int: Int] = [:]
    @ObservationIgnored private var runner: Task<Void, Never>?
    @ObservationIgnored private var prepared: Set<Int> = []
    @ObservationIgnored private let folder = Storage.folder("chapters", backedUp: false)

    private init() {
        index = Offline.read("downloads", as: [Int: Entry].self) ?? [:]
        for entry in index.values { counts[entry.manga, default: 0] += 1 }
    }

    private func folder(for chapter: Int) -> URL {
        folder.appendingPathComponent(String(chapter), isDirectory: true)
    }

    private func saveIndex() {
        Offline.write("downloads", lock.withLock { index })
    }

    // MARK: Asking

    func has(_ chapter: Int) -> Bool {
        _ = revision
        return lock.withLock { index[chapter] != nil }
    }

    func count(manga: Int) -> Int {
        _ = revision
        return lock.withLock { counts[manga] ?? 0 }
    }

    func isQueued(manga: Int) -> Bool {
        lock.withLock { (queuedManga[manga] ?? 0) > 0 }
    }

    /// The saved pages as file addresses, or nil if the chapter isn't on the phone.
    func pages(of chapter: Int) -> [String]? {
        guard let entry = lock.withLock({ index[chapter] }) else { return nil }
        let folder = folder(for: chapter)
        return (0..<entry.pages).map { folder.appendingPathComponent(String($0)).absoluteString }
    }

    var bytes: Int {
        lock.withLock { index.values.reduce(0) { $0 + $1.bytes } }
    }

    var chapterCount: Int {
        _ = revision
        return lock.withLock { index.count }
    }

    // MARK: Changing

    func enqueue(_ chapters: [Chapter], title: String) {
        let waiting = Set(queue.map(\.chapter))
        let fresh = chapters.filter { !has($0.id) && !waiting.contains($0.id) }
        guard !fresh.isEmpty else { return }
        queue += fresh.map { Job(chapter: $0.id, manga: $0.mangaId, title: $0.manga?.title ?? title, name: $0.name) }
        lock.withLock {
            for chapter in fresh { queuedManga[chapter.mangaId, default: 0] += 1 }
        }
        for chapter in fresh { progress[chapter.id] = 0 }
        problem = nil
        run()
    }

    func cancel(_ chapter: Int) {
        guard let job = queue.first(where: { $0.chapter == chapter }) else { return }
        queue.removeAll { $0.chapter == chapter }
        progress[chapter] = nil
        lock.withLock { queuedManga[job.manga, default: 1] -= 1 }
        try? FileManager.default.removeItem(at: folder(for: chapter))
    }

    func cancelAll() {
        for job in queue { cancel(job.chapter) }
    }

    func delete(_ chapters: [Int]) {
        var touched: Set<Int> = []
        lock.withLock {
            for chapter in chapters {
                guard let entry = index.removeValue(forKey: chapter) else { continue }
                counts[entry.manga, default: 1] -= 1
                touched.insert(entry.manga)
            }
        }
        for chapter in chapters { try? FileManager.default.removeItem(at: folder(for: chapter)) }
        saveIndex()
        revision += 1
        for manga in touched { Offline.forget(manga: manga) }
    }

    func deleteAll() {
        delete(lock.withLock { Array(index.keys) })
    }

    /// A queue that stopped on an error picks up again, for when the app comes back to the front.
    func retry() {
        guard problem != nil else { return }
        problem = nil
        paused = false
    }

    // MARK: Working through the queue

    private func run() {
        guard runner == nil, !paused, !queue.isEmpty else { return }
        runner = Task { @MainActor in
            while !paused, let job = queue.first {
                do {
                    try await fetch(job)
                } catch is CancellationError {
                } catch {
                    // Stop rather than hammer a server that isn't answering.
                    if queue.contains(job) {
                        problem = error.localizedDescription
                        runner = nil
                        paused = true
                        return
                    }
                }
                if queue.first == job {
                    queue.removeFirst()
                    progress[job.chapter] = nil
                    lock.withLock { queuedManga[job.manga, default: 1] -= 1 }
                }
            }
            runner = nil
        }
    }

    @MainActor private func fetch(_ job: Job) async throws {
        if prepared.insert(job.manga).inserted { await Offline.keep(manga: job.manga) }

        let paths = try await API.remotePages(of: job.chapter)
        let folder = folder(for: job.chapter)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var bytes = 0
        var done = 0
        try await withThrowingTaskGroup(of: Int.self) { group in
            var next = 0
            while next < min(3, paths.count) {
                group.addTask { [n = next] in try await Self.save(paths[n], to: folder.appendingPathComponent(String(n))) }
                next += 1
            }
            while let size = try await group.next() {
                guard queue.contains(job) else {
                    group.cancelAll()
                    throw CancellationError()
                }
                bytes += size
                done += 1
                progress[job.chapter] = Double(done) / Double(paths.count)
                if next < paths.count {
                    group.addTask { [n = next] in try await Self.save(paths[n], to: folder.appendingPathComponent(String(n))) }
                    next += 1
                }
            }
        }

        lock.withLock {
            index[job.chapter] = Entry(manga: job.manga, pages: paths.count, bytes: bytes)
            counts[job.manga, default: 0] += 1
        }
        saveIndex()
        revision += 1
    }

    /// One page to its file. A page already there from an interrupted run is kept.
    private static func save(_ path: String, to file: URL) async throws -> Int {
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 { return size }
        guard let url = Server.shared.url(path) else { throw APIError(message: "No server set") }
        let (data, response) = try await GQL.session.data(for: Server.shared.request(url))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError(message: "The server answered \(http.statusCode) for a page")
        }
        try data.write(to: file, options: .atomic)
        return data.count
    }
}
