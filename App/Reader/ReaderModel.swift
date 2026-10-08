import SwiftUI

/// What the reader scrolls through: the pages, with a card either side for the neighbouring chapters.
enum ReaderItem: Hashable {
    case before
    case page(Int)
    case after
}

@Observable final class ReaderModel {
    let mangaID: Int
    var manga: Manga?
    /// Oldest first, the order they're read in.
    var chapters: [Chapter] = []
    var chapter: Chapter?
    var pages: [String] = []
    var current: ReaderItem = .page(0)
    var page = 0
    /// Where the scroll view opens.
    var start = 0
    /// Goes up with every chapter or mode change, so the scroll view is rebuilt at `start`.
    var session = 0
    var loading = true
    var problem: String?
    var mode: ReadingMode
    var rotation: ReaderRotation
    /// True once a page of this chapter has been on screen, so the cards either side can be trusted.
    var settled = false
    /// Width over height for strip pages that have loaded, so they keep their place.
    var aspects: [Int: CGFloat] = [:]

    private var saving: Task<Void, Never>?
    private var unsaved: Int?

    init(manga: Int) {
        mangaID = manga
        mode = ReadingMode.saved(for: manga) ?? .standard
        rotation = ReaderRotation.saved(for: manga) ?? .standard
    }

    private var index: Int? { chapters.firstIndex { $0.id == chapter?.id } }
    var previous: Chapter? { index.flatMap { $0 > 0 ? chapters[$0 - 1] : nil } }
    var next: Chapter? { index.flatMap { $0 + 1 < chapters.count ? chapters[$0 + 1] : nil } }

    var items: [ReaderItem] {
        (previous == nil ? [] : [.before]) + pages.indices.map(ReaderItem.page) + [.after]
    }

    func open(_ id: Int, atEnd: Bool = false) async {
        await flush()
        loading = true
        settled = false
        problem = nil
        do {
            if chapters.isEmpty {
                async let manga = API.manga(mangaID)
                async let chapters = API.chapters(of: mangaID)
                self.manga = try await manga
                self.chapters = try await chapters.sorted { $0.sourceOrder < $1.sourceOrder }
            }
            chapter = chapters.first { $0.id == id }
            pages = try await API.pages(of: id)
            aspects = [:]
            if atEnd {
                start = max(pages.count - 1, 0)
            } else if let chapter, !chapter.isRead, chapter.lastPageRead < pages.count {
                start = chapter.lastPageRead
            } else {
                start = 0
            }
            page = start
            current = .page(start)
            session += 1
            warm(after: start)
        } catch {
            problem = error.localizedDescription
        }
        loading = false
    }

    func use(_ mode: ReadingMode) {
        guard mode != self.mode else { return }
        ReadingMode.save(mode, for: mangaID)
        start = page
        self.mode = mode
        session += 1
    }

    func use(_ rotation: ReaderRotation) {
        ReaderRotation.save(rotation, for: mangaID)
        self.rotation = rotation
    }

    /// The scroll view landed on something.
    func arrived(_ item: ReaderItem) {
        current = item
        if case .page = item { settled = true }
        guard case .page(let number) = item, number != page || unsaved == nil else { return }
        page = number
        warm(after: number)
        guard !UserDefaults.standard.bool(forKey: Keys.incognito) else { return }
        unsaved = number
        saving?.cancel()
        saving = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// Writes the page reached to the server, and marks the chapter read at its last page.
    func flush() async {
        saving?.cancel()
        guard let number = unsaved, let id = chapter?.id else { return }
        unsaved = nil
        let finished = number >= pages.count - 1
        if finished, let index { chapters[index].isRead = true }
        if let index { chapters[index].lastPageRead = number }
        try? await API.update(chapters: [id], read: finished ? true : nil, lastPage: number)
    }

    func toggleBookmark() {
        guard let index else { return }
        let value = !chapters[index].isBookmarked
        chapters[index].isBookmarked = value
        chapter = chapters[index]
        let id = chapters[index].id
        Task { try? await API.update(chapters: [id], bookmarked: value) }
    }

    private func warm(after number: Int) {
        for path in pages.dropFirst(number + 1).prefix(4) {
            if let url = Server.shared.url(path) { ImageStore.shared.warm(url) }
        }
    }
}
