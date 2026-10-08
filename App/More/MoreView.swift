import SwiftUI

struct MoreView: View {
    @AppStorage(Keys.downloadedOnly) private var downloadedOnly = false
    @AppStorage(Keys.incognito) private var incognito = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $downloadedOnly) {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Downloaded only")
                            Text("Filters all entries in your library").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "icloud.slash")
                    }
                }
                Toggle(isOn: $incognito) {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Incognito mode")
                            Text("Pauses reading history").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "eyeglasses")
                    }
                }
            }
            Section {
                NavigationLink {
                    DownloadQueueView()
                } label: {
                    Label("Download queue", systemImage: "arrow.down.circle").badge(Downloads.shared.queue.count)
                }
                NavigationLink {
                    CategoriesView()
                } label: {
                    Label("Categories", systemImage: "tag")
                }
                NavigationLink {
                    StatisticsView()
                } label: {
                    Label("Statistics", systemImage: "chart.bar")
                }
            }
            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("More")
    }
}

// MARK: - Download queue

struct DownloadQueueView: View {
    var body: some View {
        let downloads = Downloads.shared
        List {
            if let problem = downloads.problem {
                Text(verbatim: problem).font(.footnote).foregroundStyle(.red)
            }
            ForEach(downloads.queue) { job in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: job.title).font(.body).lineLimit(1)
                    HStack {
                        Text(verbatim: job.name).lineLimit(1)
                        Spacer()
                        Text((downloads.progress[job.chapter] ?? 0).formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    ProgressView(value: downloads.progress[job.chapter] ?? 0)
                }
                .swipeActions {
                    Button("Cancel", systemImage: "xmark", role: .destructive) {
                        downloads.cancel(job.chapter)
                    }
                }
            }
        }
        .overlay {
            if downloads.queue.isEmpty {
                ContentUnavailableView("No downloads", systemImage: "arrow.down.circle")
            }
        }
        .navigationTitle("Download queue")
        .inlineTitle()
        .toolbar {
            if !downloads.queue.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(downloads.paused ? "Resume" : "Pause", systemImage: downloads.paused ? "play.fill" : "pause.fill") {
                        downloads.paused.toggle()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Cancel all", systemImage: "trash") {
                        downloads.cancelAll()
                    }
                }
            }
        }
    }
}

// MARK: - Categories

struct CategoriesView: View {
    @Environment(AppModel.self) private var app
    @State private var categories: [Category] = []
    @State private var loaded = false
    @State private var adding = false
    @State private var renaming: Category?
    @State private var name = ""

    var body: some View {
        List {
            ForEach(categories) { category in
                Button {
                    name = category.name
                    renaming = category
                } label: {
                    Text(verbatim: category.name).foregroundStyle(.primary)
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        run { try await API.deleteCategory(category.id) }
                    }
                }
            }
            .onMove { from, to in
                guard let source = from.first else { return }
                let moved = categories[source]
                categories.move(fromOffsets: from, toOffset: to)
                let position = (categories.firstIndex(of: moved) ?? 0) + 1
                run { try await API.moveCategory(moved.id, to: position) }
            }
        }
        .overlay {
            if loaded, categories.isEmpty {
                ContentUnavailableView("No categories", systemImage: "tag",
                                       description: Text("Add one to split your library into tabs."))
            }
        }
        .navigationTitle("Categories")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") {
                    name = ""
                    adding = true
                }
            }
        }
        .alert("New category", isPresented: $adding) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                let text = name.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { run { try await API.createCategory(text) } }
            }
        }
        .alert("Rename category", isPresented: .init(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { category in
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let text = name.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { run { try await API.renameCategory(category.id, to: text) } }
            }
        }
        .task { await load() }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            try? await work()
            await load()
            app.revision += 1
        }
    }

    private func load() async {
        if let all = try? await API.categories() { categories = all.filter { $0.id != 0 } }
        loaded = true
    }
}

// MARK: - Statistics

struct StatisticsView: View {
    @State private var mangas: [Manga]?

    var body: some View {
        List {
            if let mangas {
                let total = mangas.reduce(0) { $0 + $1.total }
                let unread = mangas.reduce(0) { $0 + $1.unread }
                Section("Entries") {
                    LabeledContent("In library", value: mangas.count.formatted())
                    LabeledContent("Completed", value: mangas.filter { $0.status == "COMPLETED" }.count.formatted())
                    LabeledContent("Started", value: mangas.filter { $0.total - $0.unread > 0 }.count.formatted())
                    LabeledContent("Sources", value: Set(mangas.compactMap(\.sourceId)).count.formatted())
                }
                Section("Chapters") {
                    LabeledContent("Total", value: total.formatted())
                    LabeledContent("Read", value: (total - unread).formatted())
                    LabeledContent("Downloaded", value: mangas.reduce(0) { $0 + $1.downloaded }.formatted())
                }
            }
        }
        .overlay { if mangas == nil { ProgressView() } }
        .navigationTitle("Statistics")
        .inlineTitle()
        .task { mangas = try? await API.library() }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage(Keys.appearance) private var appearance = "system"
    @State private var about: AboutServer?
    @State private var cacheBytes: Int?
    @State private var changingServer = false
    @State private var deletingDownloads = false
    @State private var unsent = 0

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }
            Section {
                NavigationLink("Reader") { ReaderSettings(model: nil) }
            }
            Section("Browse") {
                NavigationLink("Extension repos") { ReposView() }
            }
            Section("Data and storage") {
                LabeledContent("Image cache", value: cacheBytes.map { $0.formatted(.byteCount(style: .file)) } ?? "")
                Button("Clear image cache") {
                    ImageStore.shared.clear()
                    cacheBytes = 0
                }
                LabeledContent("Downloaded chapters") {
                    Text(verbatim: "\(Downloads.shared.chapterCount) · \(Downloads.shared.bytes.formatted(.byteCount(style: .file)))")
                }
                Button("Delete all downloads", role: .destructive) { deletingDownloads = true }
                    .disabled(Downloads.shared.chapterCount == 0)
                if unsent > 0 {
                    LabeledContent("Progress waiting to sync", value: unsent.formatted())
                }
            }
            Section("Server") {
                LabeledContent("Address", value: Server.shared.base?.absoluteString ?? "")
                if let login = Server.shared.login {
                    LabeledContent("Signed in as", value: login.username)
                }
                if let about {
                    LabeledContent("Version", value: "\(about.version) \(about.buildType)")
                }
                Button("Change server", role: .destructive) { changingServer = true }
            }
            Section {
                LabeledContent("Yomu", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            }
        }
        .navigationTitle("Settings")
        .inlineTitle()
        .confirmationDialog("Disconnect from this server?", isPresented: $changingServer, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Server.shared.use(nil) }
        }
        .confirmationDialog("Delete every downloaded chapter?", isPresented: $deletingDownloads, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { Downloads.shared.deleteAll() }
        }
        .task {
            unsent = Marks.shared.unsent
            about = try? await API.about()
            cacheBytes = await Task.detached { ImageStore.shared.diskBytes() }.value
        }
    }
}

struct ReposView: View {
    @Environment(AppModel.self) private var app
    @State private var stores: [ExtensionStore] = []
    @State private var adding = false
    @State private var address = ""
    @State private var problem: String?

    var body: some View {
        List {
            ForEach(stores) { store in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: store.name)
                    Text(verbatim: store.indexUrl).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .swipeActions {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        run { try await API.removeStore(store.indexUrl) }
                    }
                }
            }
            if let problem {
                Text(verbatim: problem).font(.footnote).foregroundStyle(.red)
            }
        }
        .navigationTitle("Extension repos")
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") {
                    address = ""
                    adding = true
                }
            }
        }
        .alert("Add repo", isPresented: $adding) {
            TextField("Index URL", text: $address).plainField()
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { run { try await API.addStore(text) } }
            }
        }
        .task { await load() }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                problem = nil
            } catch {
                problem = error.localizedDescription
            }
            await load()
            try? await API.reloadExtensions()
            app.revision += 1
        }
    }

    private func load() async {
        if let fresh = try? await API.stores() { stores = fresh }
    }
}
