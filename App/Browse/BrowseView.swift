import SwiftUI

struct BrowseView: View {
    @State private var page = 0
    @State private var search = ""
    @State private var query: String?

    var body: some View {
        Group {
            if page == 0 {
                SourcesList()
            } else {
                ExtensionsList(search: search)
            }
        }
        .navigationTitle("Browse")
        .inlineTitle()
        .searchable(text: $search, prompt: page == 0 ? "Search every source" : "Search extensions")
        .onSubmit(of: .search) {
            let text = search.trimmingCharacters(in: .whitespaces)
            if page == 0, !text.isEmpty { query = text }
        }
        .navigationDestination(item: $query) { GlobalSearchView(query: $0) }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $page) {
                    Text("Sources").tag(0)
                    Text("Extensions").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
        }
    }
}

// MARK: - Sources

struct SourcesList: View {
    @Environment(AppModel.self) private var app
    @State private var sources: [Source] = []
    @State private var loaded = false
    @State private var problem: String?
    @State private var pinned = Stored.set(Keys.pinnedSources) ?? []
    @AppStorage(Keys.lastSource) private var lastSource = ""

    private var groups: [(title: String, sources: [Source])] {
        var result: [(String, [Source])] = []
        if let last = sources.first(where: { $0.id == lastSource }) { result.append(("Last used", [last])) }
        let pins = sources.filter { pinned.contains($0.id) }
        if !pins.isEmpty { result.append(("Pinned", pins)) }
        let rest = Dictionary(grouping: sources.filter { !pinned.contains($0.id) }, by: \.lang)
        for lang in rest.keys.sorted(by: { Lang.name($0) < Lang.name($1) }) {
            result.append((Lang.name(lang), rest[lang] ?? []))
        }
        return result
    }

    var body: some View {
        List {
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.sources) { source in
                        row(source)
                    }
                }
            }
        }
        .overlay {
            if let problem {
                Failed(message: problem) { Task { await load() } }
            } else if !loaded {
                ProgressView()
            } else if sources.allSatisfy(\.isLocal) {
                ContentUnavailableView("No sources yet", systemImage: "puzzlepiece.extension",
                                       description: Text("Install one under Extensions."))
            }
        }
        .refreshable { await load() }
        .task(id: app.revision) { await load() }
    }

    private func row(_ source: Source) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: Route.source(source, .popular)) {
                HStack(spacing: 12) {
                    IconView(path: source.iconUrl)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: source.name).font(.body)
                        Text(verbatim: Lang.name(source.lang)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if source.supportsLatest, !source.isLocal {
                NavigationLink(value: Route.source(source, .latest)) {
                    Text("Latest").font(.subheadline.weight(.medium))
                }
                .buttonStyle(.glass)
                .fixedSize()
            }
        }
        .swipeActions(edge: .leading) {
            let isPinned = pinned.contains(source.id)
            Button(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin") {
                if isPinned { pinned.remove(source.id) } else { pinned.insert(source.id) }
                Stored.save(pinned, Keys.pinnedSources)
            }
            .tint(.orange)
        }
    }

    private func load() async {
        do {
            sources = try await API.sources().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            problem = nil
        } catch is CancellationError {
        } catch {
            if !loaded { problem = error.localizedDescription }
        }
        loaded = true
    }
}

// MARK: - One source

@Observable final class SourceModel {
    let source: Source
    var listing: API.Listing
    var query = ""
    var mangas: [Manga] = []
    var page = 0
    var more = true
    var loading = false
    var problem: String?
    private var generation = 0

    init(source: Source, listing: API.Listing) {
        self.source = source
        self.listing = listing
    }

    func restart() async {
        generation += 1
        mangas = []
        page = 0
        more = true
        loading = false
        problem = nil
        await next()
    }

    func next() async {
        guard more, !loading else { return }
        loading = true
        let mine = generation
        do {
            let result = try await API.browse(source: source.id, listing, page: page + 1, query: listing == .search ? query : nil)
            guard mine == generation else { return }
            let known = Set(mangas.map(\.id))
            mangas += result.mangas.filter { !known.contains($0.id) }
            page += 1
            more = result.more && !result.mangas.isEmpty
            problem = nil
        } catch {
            guard mine == generation else { return }
            problem = error.localizedDescription
            more = false
        }
        loading = false
    }
}

struct SourceView: View {
    @State private var model: SourceModel
    @State private var search = ""
    @AppStorage(Keys.libraryColumns) private var columns = 0
    @AppStorage(Keys.lastSource) private var lastSource = ""

    init(source: Source, listing: API.Listing) {
        _model = State(initialValue: SourceModel(source: source, listing: listing))
    }

    var body: some View {
        ScrollView {
            HStack(spacing: 8) {
                chip("Popular", "heart.fill", .popular)
                if model.source.supportsLatest { chip("Latest", "clock.fill", .latest) }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            LazyVGrid(columns: Grid.columns(columns), spacing: 12) {
                ForEach($model.mangas) { $manga in
                    SourceCard(manga: $manga)
                        .onAppear {
                            if manga.id == model.mangas.last?.id { Task { await model.next() } }
                        }
                }
            }
            .padding(.horizontal, 12)
            if model.loading, !model.mangas.isEmpty {
                ProgressView().padding()
            }
        }
        .overlay {
            if model.mangas.isEmpty {
                if let problem = model.problem {
                    Failed(message: problem) { Task { await model.restart() } }
                } else if model.loading || model.page == 0 {
                    ProgressView()
                } else {
                    ContentUnavailableView("No results", systemImage: "magnifyingglass")
                }
            }
        }
        .navigationTitle(model.source.name)
        .inlineTitle()
        .searchable(text: $search, prompt: "Search \(model.source.name)")
        .onSubmit(of: .search) {
            let text = search.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return }
            model.query = text
            model.listing = .search
            Task { await model.restart() }
        }
        .task {
            lastSource = model.source.id
            if model.page == 0 { await model.restart() }
        }
    }

    private func chip(_ title: String, _ symbol: String, _ listing: API.Listing) -> some View {
        Button {
            model.listing = listing
            search = ""
            Task { await model.restart() }
        } label: {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
        }
        .buttonStyle(model.listing == listing ? AnyButtonStyle(.glassProminent) : AnyButtonStyle(.glass))
    }
}

// MARK: - Every source at once

struct GlobalSearchView: View {
    let query: String

    @State private var sources: [Source] = []
    @State private var results: [String: [Manga]] = [:]
    @State private var failed: [String: String] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLink(value: Route.source(source, .popular)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: source.name).font(.headline)
                                    Text(verbatim: Lang.name(source.lang)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        strip(source)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle(query)
        .inlineTitle()
        .task {
            guard sources.isEmpty else { return }
            sources = ((try? await API.sources()) ?? []).filter { !$0.isLocal }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            await withTaskGroup(of: (String, Result<[Manga], Error>).self) { group in
                for source in sources {
                    group.addTask {
                        do {
                            return (source.id, .success(try await API.browse(source: source.id, .search, page: 1, query: query).mangas))
                        } catch {
                            return (source.id, .failure(error))
                        }
                    }
                }
                for await (id, result) in group {
                    switch result {
                    case .success(let mangas): results[id] = mangas
                    case .failure(let error): failed[id] = error.localizedDescription
                    }
                }
            }
        }
    }

    @ViewBuilder private func strip(_ source: Source) -> some View {
        if let mangas = results[source.id] {
            if mangas.isEmpty {
                Text("No results").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 10) {
                        ForEach(mangas) { manga in
                            NavigationLink(value: Route.manga(manga.id)) {
                                MangaCard(title: manga.title, cover: manga.thumbnailUrl, display: .comfortable,
                                          inLibrary: manga.isInLibrary)
                                    .frame(width: 104)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
            }
        } else if let message = failed[source.id] {
            Text(verbatim: message).font(.subheadline).foregroundStyle(.secondary).lineLimit(2).padding(.horizontal, 16)
        } else {
            ProgressView().frame(maxWidth: .infinity).frame(height: 60)
        }
    }
}
