import SwiftUI

@Observable final class MangaModel {
    let id: Int
    var manga: Manga?
    var chapters: [Chapter] = []
    var loaded = false
    var refreshing = false
    var problem: String?

    init(id: Int) {
        self.id = id
    }

    func load() async {
        do {
            async let manga = API.manga(id)
            async let chapters = API.chapters(of: id)
            (self.manga, self.chapters) = try await (manga, chapters)
            problem = nil
            let first = !loaded
            loaded = true
            if first, self.chapters.isEmpty { await refresh() }
        } catch is CancellationError {
        } catch {
            if !loaded { problem = error.localizedDescription }
            loaded = true
        }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        do {
            let cover = manga?.thumbnailUrl
            (manga, chapters) = try await API.refresh(manga: id)
            if let url = Server.shared.url(cover) { ImageStore.shared.forget(url) }
            problem = nil
        } catch {
            if chapters.isEmpty { problem = error.localizedDescription }
        }
        refreshing = false
    }

    /// Reading order is oldest first, whatever order the list is shown in.
    var ordered: [Chapter] { chapters.sorted { $0.sourceOrder < $1.sourceOrder } }

    var next: Chapter? { ordered.first { !$0.isRead } }
    var started: Bool { chapters.contains { $0.isRead || $0.lastPageRead > 0 } }

    func set(_ ids: [Int], read: Bool? = nil, bookmarked: Bool? = nil) async {
        for index in chapters.indices where ids.contains(chapters[index].id) {
            if let read {
                chapters[index].isRead = read
                if !read { chapters[index].lastPageRead = 0 }
            }
            if let bookmarked { chapters[index].isBookmarked = bookmarked }
        }
        try? await API.update(chapters: ids, read: read, bookmarked: bookmarked, lastPage: read == false ? 0 : nil)
    }

    /// Queues chapters to be saved on the phone, oldest first.
    func download(_ ids: [Int]) {
        let wanted = Set(ids)
        Downloads.shared.enqueue(ordered.filter { wanted.contains($0.id) }, title: manga?.title ?? "")
    }
}

struct MangaView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var model: MangaModel
    @State private var expanded = false
    @State private var showFilter = false
    @State private var categories: [Category]?

    @AppStorage(Keys.chapterSort) private var sort = ChapterSort.source
    @AppStorage(Keys.chapterAscending) private var ascending = false
    @AppStorage(Keys.chapterUnread) private var filterUnread = 0
    @AppStorage(Keys.chapterDownloaded) private var filterDownloaded = 0
    @AppStorage(Keys.chapterBookmarked) private var filterBookmarked = 0
    @AppStorage(Keys.downloadedOnly) private var downloadedOnly = false

    init(id: Int) {
        _model = State(initialValue: MangaModel(id: id))
    }

    private var shown: [Chapter] {
        func tri(_ raw: Int) -> Tri { Tri(rawValue: raw) ?? .off }
        let kept = model.chapters.filter {
            tri(filterUnread).allows(!$0.isRead) && tri(filterDownloaded).allows($0.isDownloaded)
                && tri(filterBookmarked).allows($0.isBookmarked) && (!downloadedOnly || $0.isDownloaded)
        }
        let sorted = kept.sorted { sort.ordered($0, before: $1) }
        return ascending ? sorted : sorted.reversed()
    }

    private var filtering: Bool { filterUnread + filterDownloaded + filterBookmarked > 0 }

    var body: some View {
        let shown = shown
        List {
            if let manga = model.manga {
                header(manga)
                    .listRowInsets(.init())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                Section {
                    ForEach(shown) { chapter in
                        row(chapter)
                    }
                } header: {
                    HStack {
                        Text(verbatim: "\(shown.count) \(shown.count == 1 ? "chapter" : "chapters")")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if model.refreshing { ProgressView().controlSize(.small) }
                        Spacer()
                        Button("Filter", systemImage: filtering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease") {
                            showFilter = true
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if let problem = model.problem, model.manga == nil {
                Failed(message: problem) { Task { await model.load() } }
            } else if model.manga == nil {
                ProgressView()
            }
        }
        .inlineTitle()
        .refreshable { await model.refresh() }
        .safeAreaInset(edge: .bottom, alignment: .trailing) {
            if let next = model.next {
                Button {
                    app.reading = ReaderRequest(manga: model.id, chapter: next.id)
                } label: {
                    Label(model.started ? "Resume" : "Start", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .toolbar { toolbar }
        .sheet(isPresented: $showFilter) { ChapterOptions() }
        .sheet(isPresented: .init(get: { categories != nil }, set: { if !$0 { categories = nil } })) {
            if let manga = model.manga, let categories {
                CategoryPicker(manga: manga, categories: categories) {
                    Task { await model.load() }
                    app.revision += 1
                }
            }
        }
        .task { await model.load() }
        .onChange(of: app.reading == nil) { _, closed in
            if closed { Task { await model.load() } }
        }
    }

    // MARK: Header

    private func header(_ manga: Manga) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                CoverView(path: manga.thumbnailUrl, maxPixel: Cover.large)
                    .frame(width: 112)
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: manga.title)
                        .font(.title3.weight(.bold))
                        .lineLimit(5)
                        .textSelection(.enabled)
                    if let people = manga.people {
                        Label(people, systemImage: "person").lineLimit(2)
                    }
                    Label {
                        Text(verbatim: [manga.statusText, manga.source?.displayName].compactMap { $0 }.joined(separator: " · "))
                    } icon: {
                        Image(systemName: manga.statusSymbol)
                    }
                    .lineLimit(2)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                action(manga.isInLibrary ? "In library" : "Add to library",
                       manga.isInLibrary ? "heart.fill" : "heart", tinted: manga.isInLibrary) {
                    toggleLibrary(manga)
                }
                if let link = manga.realUrl.flatMap(URL.init(string:)) {
                    action("Website", "safari", tinted: false) { openURL(link) }
                    ShareLink(item: link) {
                        tile("Share", "square.and.arrow.up", tinted: false)
                    }
                    .buttonStyle(.glass)
                }
            }
            if let text = manga.description?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                Text(verbatim: text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
            }
            if let genres = manga.genre, !genres.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(genres, id: \.self) { genre in
                            Text(verbatim: genre)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.fill.tertiary, in: .capsule)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(alignment: .top) {
            RemoteImage(path: manga.thumbnailUrl, maxPixel: Cover.grid)
                .frame(height: 320)
                .blur(radius: 40)
                .opacity(0.4)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .padding(.top, -200)
                .allowsHitTesting(false)
        }
    }

    private func tile(_ title: String, _ symbol: String, tinted: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.body.weight(.semibold))
            Text(verbatim: title).font(.caption.weight(.medium)).lineLimit(1)
        }
        .foregroundStyle(tinted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func action(_ title: String, _ symbol: String, tinted: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { tile(title, symbol, tinted: tinted) }
            .buttonStyle(.glass)
    }

    private func toggleLibrary(_ manga: Manga) {
        let value = !manga.isInLibrary
        model.manga?.inLibrary = value
        Task {
            try? await API.setInLibrary([manga.id], value)
            app.revision += 1
            if value, let all = try? await API.categories(), all.contains(where: { $0.id != 0 }) {
                categories = all
            }
        }
    }

    // MARK: Chapters

    private func row(_ chapter: Chapter) -> some View {
        HStack(spacing: 10) {
            Button {
                app.reading = ReaderRequest(manga: model.id, chapter: chapter.id)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if chapter.isBookmarked {
                            Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.tint)
                        }
                        Text(verbatim: chapter.name).font(.body).lineLimit(1)
                    }
                    Text(verbatim: detail(chapter)).font(.caption).lineLimit(1).opacity(0.75)
                }
                .foregroundStyle(chapter.isRead ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            DownloadButton(chapter: chapter, title: model.manga?.title ?? "")
        }
        .swipeActions(edge: .leading) {
            Button(chapter.isRead ? "Unread" : "Read", systemImage: chapter.isRead ? "circle" : "checkmark") {
                Task { await model.set([chapter.id], read: !chapter.isRead) }
            }
            .tint(.accentColor)
        }
        .swipeActions(edge: .trailing) {
            Button(chapter.isBookmarked ? "Unbookmark" : "Bookmark", systemImage: chapter.isBookmarked ? "bookmark.slash" : "bookmark") {
                Task { await model.set([chapter.id], bookmarked: !chapter.isBookmarked) }
            }
            .tint(.orange)
        }
        .contextMenu {
            Button(chapter.isRead ? "Mark as unread" : "Mark as read", systemImage: chapter.isRead ? "circle" : "checkmark") {
                Task { await model.set([chapter.id], read: !chapter.isRead) }
            }
            Button("Mark previous as read", systemImage: "checkmark.rectangle.stack") {
                let ids = model.chapters.filter { $0.sourceOrder < chapter.sourceOrder && !$0.isRead }.map(\.id)
                Task { await model.set(ids, read: true) }
            }
            Button(chapter.isBookmarked ? "Remove bookmark" : "Bookmark", systemImage: chapter.isBookmarked ? "bookmark.slash" : "bookmark") {
                Task { await model.set([chapter.id], bookmarked: !chapter.isBookmarked) }
            }
            if chapter.isDownloaded {
                Button("Delete download", systemImage: "trash", role: .destructive) {
                    Downloads.shared.delete([chapter.id])
                }
            } else {
                Button("Download", systemImage: "arrow.down.circle") {
                    model.download([chapter.id])
                }
            }
        }
    }

    private func detail(_ chapter: Chapter) -> String {
        var parts: [String] = []
        if let date = chapter.uploaded { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
        if !chapter.isRead, chapter.lastPageRead > 0 { parts.append("Page \(chapter.lastPageRead + 1)") }
        if let scanlator = chapter.scanlator, !scanlator.isEmpty { parts.append(scanlator) }
        return parts.joined(separator: " · ")
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu("Download", systemImage: "arrow.down.circle") {
                Button("Next chapter") { downloadNext(1) }
                Button("Next 5 chapters") { downloadNext(5) }
                Button("Next 10 chapters") { downloadNext(10) }
                Button("Unread") { downloadNext(.max) }
                Button("All") {
                    model.download(model.chapters.map(\.id))
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu("More", systemImage: "ellipsis") {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                if model.manga?.isInLibrary == true {
                    Button("Set categories", systemImage: "tag") {
                        Task { categories = try? await API.categories() }
                    }
                }
                Button("Mark all as read", systemImage: "checkmark") {
                    Task { await model.set(model.chapters.filter { !$0.isRead }.map(\.id), read: true) }
                }
                Button("Mark all as unread", systemImage: "circle") {
                    Task { await model.set(model.chapters.filter(\.isRead).map(\.id), read: false) }
                }
            }
        }
    }

    private func downloadNext(_ count: Int) {
        model.download(model.ordered.filter { !$0.isRead && !$0.isDownloaded }.prefix(count).map(\.id))
    }
}

/// Filter and sort for a chapter list.
struct ChapterOptions: View {
    @State private var page = 0
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Keys.chapterSort) private var sort = ChapterSort.source
    @AppStorage(Keys.chapterAscending) private var ascending = false
    @AppStorage(Keys.chapterUnread) private var filterUnread = 0
    @AppStorage(Keys.chapterDownloaded) private var filterDownloaded = 0
    @AppStorage(Keys.chapterBookmarked) private var filterBookmarked = 0

    var body: some View {
        NavigationStack {
            Form {
                if page == 0 {
                    TriRow(title: "Downloaded", value: $filterDownloaded)
                    TriRow(title: "Unread", value: $filterUnread)
                    TriRow(title: "Bookmarked", value: $filterBookmarked)
                } else {
                    ForEach(ChapterSort.allCases) { option in
                        SortRow(title: option.title, chosen: sort == option, ascending: ascending) {
                            if sort == option { ascending.toggle() } else { sort = option }
                        }
                    }
                }
            }
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Page", selection: $page) {
                        Text("Filter").tag(0)
                        Text("Sort").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
