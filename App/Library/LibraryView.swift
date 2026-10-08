import SwiftUI

@Observable final class LibraryModel {
    var mangas: [Manga] = []
    var categories: [Category] = []
    var loaded = false
    var problem: String?
    var jobs: UpdateJobs?

    func load() async {
        do {
            async let mangas = API.library()
            async let categories = API.categories()
            (self.mangas, self.categories) = try await (mangas, categories)
            problem = nil
        } catch is CancellationError {
        } catch {
            if !loaded { problem = error.localizedDescription }
        }
        loaded = true
    }

    /// Starts the server checking for new chapters and follows it until it's done.
    func update(category: Int? = nil) async {
        guard jobs == nil else { return }
        do {
            try await API.updateLibrary(category: category)
            repeat {
                try await Task.sleep(for: .seconds(1))
                jobs = try await API.updateJobs()
            } while jobs?.isRunning == true
        } catch {}
        jobs = nil
        await load()
    }

    /// Categories worth a tab: the user's own, and Default only while something is still in it.
    var tabs: [Category] {
        let hasUncategorised = mangas.contains { $0.categoryIDs.isEmpty }
        return categories.filter { $0.id != 0 || hasUncategorised }
    }

    func mangas(in category: Category?) -> [Manga] {
        guard let category, tabs.count > 1 else { return mangas }
        return mangas.filter { category.id == 0 ? $0.categoryIDs.isEmpty : $0.categoryIDs.contains(category.id) }
    }
}

struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @State private var model = LibraryModel()
    @State private var search = ""
    @State private var showOptions = false
    @State private var path: Int?
    @State private var categorising: Manga?
    @State private var removing: Manga?

    @AppStorage(Keys.libraryCategory) private var categoryID = 0
    @AppStorage(Keys.libraryDisplay) private var display = LibraryDisplay.compact
    @AppStorage(Keys.librarySort) private var sort = LibrarySort.alphabetical
    @AppStorage(Keys.libraryAscending) private var ascending = true
    @AppStorage(Keys.libraryColumns) private var columns = 0
    @AppStorage(Keys.unreadBadge) private var unreadBadge = true
    @AppStorage(Keys.downloadBadge) private var downloadBadge = true
    @AppStorage(Keys.filterDownloaded) private var filterDownloaded = 0
    @AppStorage(Keys.filterUnread) private var filterUnread = 0
    @AppStorage(Keys.filterStarted) private var filterStarted = 0
    @AppStorage(Keys.filterBookmarked) private var filterBookmarked = 0
    @AppStorage(Keys.filterCompleted) private var filterCompleted = 0
    @AppStorage(Keys.downloadedOnly) private var downloadedOnly = false

    private var category: Category? {
        model.tabs.first { $0.id == categoryID } ?? model.tabs.first
    }

    private var filtering: Bool {
        filterDownloaded + filterUnread + filterStarted + filterBookmarked + filterCompleted > 0 || downloadedOnly
    }

    private var shown: [Manga] {
        func tri(_ raw: Int) -> Tri { Tri(rawValue: raw) ?? .off }
        let query = search.trimmingCharacters(in: .whitespaces)
        let pool = query.isEmpty ? model.mangas(in: category) : model.mangas
        let kept = pool.filter { manga in
            (query.isEmpty || manga.title.localizedCaseInsensitiveContains(query))
                && (!downloadedOnly || manga.downloaded > 0)
                && tri(filterDownloaded).allows(manga.downloaded > 0)
                && tri(filterUnread).allows(manga.unread > 0)
                && tri(filterStarted).allows(manga.total - manga.unread > 0)
                && tri(filterBookmarked).allows((manga.bookmarkCount ?? 0) > 0)
                && tri(filterCompleted).allows(manga.status == "COMPLETED")
        }
        let sorted = kept.sorted { sort.ordered($0, before: $1) }
        return ascending ? sorted : sorted.reversed()
    }

    var body: some View {
        let shown = shown
        ScrollView {
            if model.tabs.count > 1, search.isEmpty {
                tabs
            }
            if display == .list {
                LazyVStack(spacing: 0) {
                    ForEach(shown) { manga in
                        entry(manga) {
                            HStack(spacing: 12) {
                                RowCover(path: manga.thumbnailUrl)
                                Text(verbatim: manga.title).font(.body).lineLimit(2).multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                badges(manga).foregroundStyle(.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .contentShape(.rect)
                        }
                    }
                }
            } else {
                LazyVGrid(columns: Grid.columns(columns), spacing: 12) {
                    ForEach(shown) { manga in
                        entry(manga) {
                            MangaCard(title: manga.title, cover: manga.thumbnailUrl, display: display,
                                      unread: unreadBadge ? manga.unread : 0,
                                      downloaded: downloadBadge ? manga.downloaded : 0)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .overlay {
            if let problem = model.problem {
                Failed(message: problem) { Task { await model.load() } }
            } else if !model.loaded {
                ProgressView()
            } else if model.mangas.isEmpty {
                ContentUnavailableView("Your library is empty", systemImage: "books.vertical",
                                       description: Text("Series you add from Browse show up here."))
            } else if shown.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView("Nothing matches", systemImage: "line.3.horizontal.decrease")
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
        .navigationTitle("Library")
        .searchable(text: $search, prompt: "Search library")
        .refreshable { await model.update() }
        .toolbar {
            if let jobs = model.jobs, jobs.totalJobs > 0 {
                ToolbarItem(placement: .principal) {
                    ProgressView(value: Double(jobs.finishedJobs), total: Double(max(jobs.totalJobs, 1)))
                        .frame(width: 120)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Filter", systemImage: filtering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease") {
                    showOptions = true
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Update library", systemImage: "arrow.clockwise") {
                        Task { await model.update() }
                    }
                    if let category, model.tabs.count > 1 {
                        Button("Update category", systemImage: "arrow.clockwise.square") {
                            Task { await model.update(category: category.id) }
                        }
                    }
                    Button("Open random entry", systemImage: "shuffle") {
                        path = shown.randomElement()?.id
                    }
                    .disabled(shown.isEmpty)
                }
            }
        }
        .navigationDestination(item: $path) { MangaView(id: $0) }
        .sheet(isPresented: $showOptions) { LibraryOptions() }
        .sheet(item: $categorising) { manga in
            CategoryPicker(manga: manga, categories: model.categories) { Task { await model.load() } }
        }
        .confirmationDialog("Remove from library?", isPresented: .init(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { manga in
            Button("Remove", role: .destructive) {
                model.mangas.removeAll { $0.id == manga.id }
                Task {
                    try? await API.setInLibrary([manga.id], false)
                    await model.load()
                }
            }
        } message: { manga in
            Text(verbatim: manga.title)
        }
        .task(id: app.revision) { await model.load() }
        .onAppear { Task { await model.load() } }
    }

    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.tabs) { tab in
                    let chosen = tab.id == category?.id
                    Button {
                        withAnimation(.snappy) { categoryID = tab.id }
                    } label: {
                        HStack(spacing: 6) {
                            Text(verbatim: tab.name)
                            Text(verbatim: "\(model.mangas(in: tab).count)")
                                .font(.caption.monospacedDigit())
                                .opacity(0.7)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(chosen ? AnyButtonStyle(.glassProminent) : AnyButtonStyle(.glass))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func badges(_ manga: Manga) -> some View {
        Badges(unread: unreadBadge ? manga.unread : 0, downloaded: downloadBadge ? manga.downloaded : 0)
    }

    private func entry<Label: View>(_ manga: Manga, @ViewBuilder label: () -> Label) -> some View {
        NavigationLink(value: Route.manga(manga.id), label: label)
            .buttonStyle(.plain)
            .contextMenu {
                Button("Mark as read", systemImage: "checkmark") { mark(manga, read: true) }
                Button("Mark as unread", systemImage: "circle") { mark(manga, read: false) }
                Button("Download unread", systemImage: "arrow.down.circle") {
                    Task {
                        guard let chapters = try? await API.chapters(of: manga.id) else { return }
                        Downloads.shared.enqueue(chapters.filter { !$0.isRead }.reversed(), title: manga.title)
                    }
                }
                if model.categories.contains(where: { $0.id != 0 }) {
                    Button("Set categories", systemImage: "tag") { categorising = manga }
                }
                Divider()
                Button("Remove from library", systemImage: "trash", role: .destructive) { removing = manga }
            }
    }

    private func mark(_ manga: Manga, read: Bool) {
        Task {
            guard let chapters = try? await API.chapters(of: manga.id) else { return }
            try? await API.update(chapters: chapters.filter { $0.isRead != read }.map(\.id), read: read)
            await model.load()
        }
    }
}

/// `.buttonStyle` wants one concrete type, and the category tabs switch between two.
struct AnyButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}

/// Filter, sort and display, the same three pages as Mihon's library sheet.
struct LibraryOptions: View {
    @State private var page = 0
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Keys.libraryDisplay) private var display = LibraryDisplay.compact
    @AppStorage(Keys.librarySort) private var sort = LibrarySort.alphabetical
    @AppStorage(Keys.libraryAscending) private var ascending = true
    @AppStorage(Keys.libraryColumns) private var columns = 0
    @AppStorage(Keys.unreadBadge) private var unreadBadge = true
    @AppStorage(Keys.downloadBadge) private var downloadBadge = true
    @AppStorage(Keys.filterDownloaded) private var filterDownloaded = 0
    @AppStorage(Keys.filterUnread) private var filterUnread = 0
    @AppStorage(Keys.filterStarted) private var filterStarted = 0
    @AppStorage(Keys.filterBookmarked) private var filterBookmarked = 0
    @AppStorage(Keys.filterCompleted) private var filterCompleted = 0

    var body: some View {
        NavigationStack {
            Form {
                switch page {
                case 0:
                    TriRow(title: "Downloaded", value: $filterDownloaded)
                    TriRow(title: "Unread", value: $filterUnread)
                    TriRow(title: "Started", value: $filterStarted)
                    TriRow(title: "Bookmarked", value: $filterBookmarked)
                    TriRow(title: "Completed", value: $filterCompleted)
                case 1:
                    ForEach(LibrarySort.allCases) { option in
                        SortRow(title: option.title, chosen: sort == option, ascending: ascending) {
                            if sort == option { ascending.toggle() } else { sort = option }
                        }
                    }
                default:
                    Picker("Display mode", selection: $display) {
                        ForEach(LibraryDisplay.allCases) { Text(verbatim: $0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    if display != .list {
                        Section("Items per row") {
                            HStack {
                                Text(verbatim: columns == 0 ? "Auto" : "\(columns)").monospacedDigit().frame(width: 44, alignment: .leading)
                                Slider(value: .init(get: { Double(columns) }, set: { columns = Int($0) }), in: 0...6, step: 1)
                            }
                        }
                    }
                    Section("Badges") {
                        Toggle("Downloaded chapters", isOn: $downloadBadge)
                        Toggle("Unread chapters", isOn: $unreadBadge)
                    }
                }
            }
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Page", selection: $page) {
                        Text("Filter").tag(0)
                        Text("Sort").tag(1)
                        Text("Display").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Which categories a series sits in.
struct CategoryPicker: View {
    let manga: Manga
    let categories: [Category]
    let done: () -> Void

    @State private var chosen: Set<Int>
    @Environment(\.dismiss) private var dismiss

    init(manga: Manga, categories: [Category], done: @escaping () -> Void) {
        self.manga = manga
        self.categories = categories.filter { $0.id != 0 }
        self.done = done
        _chosen = State(initialValue: Set(manga.categoryIDs))
    }

    var body: some View {
        NavigationStack {
            List(categories) { category in
                Button {
                    if !chosen.insert(category.id).inserted { chosen.remove(category.id) }
                } label: {
                    HStack {
                        Text(verbatim: category.name).foregroundStyle(.primary)
                        Spacer()
                        if chosen.contains(category.id) { Image(systemName: "checkmark").fontWeight(.semibold) }
                    }
                }
            }
            .navigationTitle("Set categories")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        Task {
                            try? await API.setCategories(manga: manga.id, to: chosen.sorted())
                            done()
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
