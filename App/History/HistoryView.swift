import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @State private var chapters: [Chapter] = []
    @State private var loaded = false
    @State private var problem: String?
    @State private var search = ""

    /// One row per series: the chapter it was last read at.
    private var entries: [Chapter] {
        var seen = Set<Int>()
        let query = search.trimmingCharacters(in: .whitespaces)
        return chapters.filter { chapter in
            seen.insert(chapter.mangaId).inserted
                && (query.isEmpty || (chapter.manga?.title ?? "").localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        let entries = entries
        List {
            ForEach(Day.groups(entries, by: \.lastRead), id: \.day) { group in
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
                ContentUnavailableView("Nothing read recently", systemImage: "clock.arrow.circlepath")
            } else if entries.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .navigationTitle("History")
        .searchable(text: $search, prompt: "Search history")
        .refreshable { await load() }
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
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: chapter.manga?.title ?? "").font(.body).lineLimit(2)
                        HStack(spacing: 4) {
                            Text(verbatim: chapter.name).lineLimit(1)
                            if let date = chapter.lastRead {
                                Text(verbatim: "· " + date.formatted(date: .omitted, time: .shortened))
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "play.fill").foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func load() async {
        do {
            chapters = try await API.history()
            problem = nil
        } catch is CancellationError {
        } catch {
            if !loaded { problem = error.localizedDescription }
        }
        loaded = true
    }
}
