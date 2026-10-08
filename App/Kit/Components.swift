// Pieces more than one screen uses: the cover card, its badges, day headers, and the routes.

import SwiftUI

// MARK: - Routes

enum Route: Hashable {
    case manga(Int)
    case source(Source, API.Listing)
    case search(String)
}

struct ReaderRequest: Identifiable {
    let manga: Int
    let chapter: Int

    var id: Int { chapter }
}

@Observable final class AppModel {
    var reading: ReaderRequest?
    var extensionUpdates = 0
    /// Goes up whenever a screen changes something another screen shows.
    var revision = 0

    func refreshBadges() async {
        if let count = try? await API.extensionUpdates() { extensionUpdates = count }
    }
}

extension View {
    func routes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .manga(let id): MangaView(id: id)
            case .source(let source, let listing): SourceView(source: source, listing: listing)
            case .search(let query): GlobalSearchView(query: query)
            }
        }
    }
}

// MARK: - Cards

enum Grid {
    static func columns(_ count: Int) -> [GridItem] {
        count > 0
            ? Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
            : [GridItem(.adaptive(minimum: 104), spacing: 10)]
    }
}

/// The joined pills in a cover's corner: unread in the accent colour, downloads beside it.
struct Badges: View {
    var unread: Int = 0
    var downloaded: Int = 0
    var inLibrary = false

    var body: some View {
        HStack(spacing: 0) {
            if inLibrary { pill("In library", .tint) }
            if downloaded > 0 { pill("\(downloaded)", .regularMaterial) }
            if unread > 0 { pill("\(unread)", .tint) }
        }
        .clipShape(.rect(cornerRadius: 6))
    }

    private func pill<S: ShapeStyle>(_ text: String, _ style: S) -> some View {
        Text(verbatim: text)
            .font(.caption2.weight(.bold).monospacedDigit())
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(style)
    }
}

struct MangaCard: View {
    let title: String
    let cover: String?
    var display: LibraryDisplay = .compact
    var unread = 0
    var downloaded = 0
    var inLibrary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverView(path: cover)
                .overlay(alignment: .bottom) {
                    if display == .compact {
                        LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                            .clipShape(.rect(cornerRadius: 10))
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if display == .compact {
                        Text(verbatim: title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .shadow(radius: 3)
                            .padding(7)
                    }
                }
                .overlay(alignment: .topLeading) {
                    Badges(unread: unread, downloaded: downloaded, inLibrary: inLibrary)
                        .foregroundStyle(.white)
                        .padding(5)
                }
                .opacity(inLibrary ? 0.45 : 1)
            if display == .comfortable {
                Text(verbatim: title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .contentShape(.rect)
    }
}

/// Covers from a source: tap to open, hold to add or remove.
struct SourceCard: View {
    @Binding var manga: Manga
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationLink(value: Route.manga(manga.id)) {
            MangaCard(title: manga.title, cover: manga.thumbnailUrl, inLibrary: manga.isInLibrary)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(manga.isInLibrary ? "Remove from library" : "Add to library",
                   systemImage: manga.isInLibrary ? "heart.slash" : "heart") {
                let value = !manga.isInLibrary
                manga.inLibrary = value
                Task {
                    try? await API.setInLibrary([manga.id], value)
                    app.revision += 1
                }
            }
        }
    }
}

// MARK: - Lists

/// A chapter or history row's leading cover.
struct RowCover: View {
    let path: String?

    var body: some View {
        CoverView(path: path, maxPixel: Cover.icon * 2, radius: 6).frame(width: 40)
    }
}

enum Day {
    /// "Today", "Yesterday", then the date.
    static func title(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0
        if days > 0, days < 7 { return "\(days) days ago" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Splits rows into days, keeping the order they came in.
    static func groups<T>(_ items: [T], by date: (T) -> Date?) -> [(day: Date, items: [T])] {
        var result: [(day: Date, items: [T])] = []
        for item in items {
            let day = Calendar.current.startOfDay(for: date(item) ?? .distantPast)
            if result.last?.day == day {
                result[result.count - 1].items.append(item)
            } else {
                result.append((day, [item]))
            }
        }
        return result
    }
}

struct Failed: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't load", systemImage: "wifi.exclamationmark")
        } description: {
            Text(verbatim: message)
        } actions: {
            Button("Try again", action: retry).buttonStyle(.glass)
        }
    }
}

/// A row that cycles off, include, exclude.
struct TriRow: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        Button {
            value = (Tri(rawValue: value) ?? .off).next.rawValue
        } label: {
            HStack {
                Text(verbatim: title).foregroundStyle(.primary)
                Spacer()
                switch Tri(rawValue: value) ?? .off {
                case .off: Image(systemName: "square").foregroundStyle(.tertiary)
                case .include: Image(systemName: "checkmark.square.fill")
                case .exclude: Image(systemName: "xmark.square.fill")
                }
            }
            .font(.body)
        }
    }
}

/// Sort rows: tapping the chosen one flips its direction.
struct SortRow: View {
    let title: String
    let chosen: Bool
    let ascending: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(verbatim: title).foregroundStyle(.primary)
                Spacer()
                if chosen { Image(systemName: ascending ? "arrow.up" : "arrow.down").fontWeight(.semibold) }
            }
        }
    }
}
