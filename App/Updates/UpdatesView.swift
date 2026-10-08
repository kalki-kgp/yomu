import SwiftUI

struct UpdatesView: View {
    @Environment(AppModel.self) private var app
    @State private var chapters: [Chapter] = []
    @State private var loaded = false
    @State private var problem: String?
    @State private var updating = false

    var body: some View {
        List {
            ForEach(Day.groups(chapters, by: \.fetched), id: \.day) { group in
                Section {
                    ForEach(group.items) { chapter in
                        row(chapter)
                    }
                } header: {
                    Text(verbatim: Day.title(group.day))
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if let problem {
                Failed(message: problem) { Task { await load() } }
            } else if !loaded {
                ProgressView()
            } else if chapters.isEmpty {
                ContentUnavailableView("No recent updates", systemImage: "bell",
                                       description: Text("New chapters for your library show up here."))
            }
        }
        .navigationTitle("Updates")
        .refreshable { await update() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if updating {
                    ProgressView()
                } else {
                    Button("Update library", systemImage: "arrow.clockwise") { Task { await update() } }
                }
            }
        }
        .task(id: app.revision) { await load() }
        .onAppear { Task { await load() } }
    }

    private func row(_ chapter: Chapter) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: Route.manga(chapter.mangaId)) {
                RowCover(path: chapter.manga?.thumbnailUrl)
            }
            .buttonStyle(.plain)
            .frame(width: 40)
            Button {
                app.reading = ReaderRequest(manga: chapter.mangaId, chapter: chapter.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: chapter.manga?.title ?? "").font(.body).lineLimit(1)
                    HStack(spacing: 4) {
                        if chapter.isBookmarked { Image(systemName: "bookmark.fill").foregroundStyle(.tint) }
                        Text(verbatim: chapter.name).lineLimit(1)
                        if !chapter.isRead, chapter.lastPageRead > 0 {
                            Text(verbatim: "· Page \(chapter.lastPageRead + 1)").foregroundStyle(.tertiary)
                        }
                    }
                    .font(.subheadline)
                }
                .foregroundStyle(chapter.isRead ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            DownloadButton(chapter: chapter, title: chapter.manga?.title ?? "")
        }
        .swipeActions(edge: .leading) {
            Button(chapter.isRead ? "Unread" : "Read", systemImage: chapter.isRead ? "circle" : "checkmark") {
                change(chapter) { try await API.update(chapters: [chapter.id], read: !chapter.isRead) }
            }
            .tint(.accentColor)
        }
        .swipeActions(edge: .trailing) {
            Button(chapter.isBookmarked ? "Unbookmark" : "Bookmark", systemImage: chapter.isBookmarked ? "bookmark.slash" : "bookmark") {
                change(chapter) { try await API.update(chapters: [chapter.id], bookmarked: !chapter.isBookmarked) }
            }
            .tint(.orange)
        }
    }

    private func change(_ chapter: Chapter, _ work: @escaping () async throws -> Void) {
        Task {
            try? await work()
            await load()
        }
    }

    private func load() async {
        do {
            chapters = try await API.updates()
            problem = nil
        } catch is CancellationError {
        } catch {
            if !loaded { problem = error.localizedDescription }
        }
        loaded = true
    }

    private func update() async {
        guard !updating else { return }
        updating = true
        do {
            try await API.updateLibrary()
            var running = true
            while running {
                try await Task.sleep(for: .seconds(1))
                running = try await API.updateJobs().isRunning
            }
        } catch {}
        updating = false
        await load()
    }
}

/// The trailing button on a chapter row: save it to the phone, or remove the saved copy.
struct DownloadButton: View {
    let chapter: Chapter
    let title: String

    var body: some View {
        let downloads = Downloads.shared
        Group {
            if downloads.has(chapter.id) {
                Menu {
                    Button("Delete download", systemImage: "trash", role: .destructive) {
                        downloads.delete([chapter.id])
                    }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
            } else if let progress = downloads.progress[chapter.id] {
                Button {
                    downloads.cancel(chapter.id)
                } label: {
                    ProgressView(value: progress).progressViewStyle(.circular)
                }
            } else {
                Button {
                    downloads.enqueue([chapter], title: title)
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
            }
        }
        .font(.title3)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .frame(width: 32, height: 32)
    }
}
