// What the server sends, as it sends it. Fields a query doesn't ask for stay nil.

import Foundation

struct Nodes<T: Codable & Hashable>: Codable, Hashable {
    var nodes: [T]
}

struct Count: Codable, Hashable {
    var totalCount: Int
}

struct Manga: Codable, Identifiable, Hashable {
    let id: Int
    var title: String
    var thumbnailUrl: String?
    var inLibrary: Bool?
    var inLibraryAt: String?
    var author: String?
    var artist: String?
    var description: String?
    var genre: [String]?
    var status: String?
    var realUrl: String?
    var sourceId: String?
    var unreadCount: Int?
    var bookmarkCount: Int?
    var chapters: Count?
    var lastReadChapter: Stamp?
    var latestUploadedChapter: Stamp?
    var latestFetchedChapter: Stamp?
    var source: SourceName?
    var categories: Nodes<CategoryRef>?

    struct Stamp: Codable, Hashable {
        var lastReadAt: String?
        var uploadDate: String?
        var fetchedAt: String?
    }

    struct SourceName: Codable, Hashable {
        var id: String
        var displayName: String
    }

    struct CategoryRef: Codable, Hashable {
        var id: Int
    }

    var isInLibrary: Bool { inLibrary ?? false }
    var unread: Int { unreadCount ?? 0 }
    /// Chapters saved on this phone.
    var downloaded: Int { Downloads.shared.count(manga: id) }
    var total: Int { chapters?.totalCount ?? 0 }
    var categoryIDs: [Int] { categories?.nodes.map(\.id) ?? [] }

    var people: String? {
        let names = [author, artist].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var seen = Set<String>()
        let unique = names.filter { seen.insert($0).inserted }
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }

    var statusText: String {
        switch status {
        case "ONGOING": "Ongoing"
        case "COMPLETED": "Completed"
        case "LICENSED": "Licensed"
        case "PUBLISHING_FINISHED": "Publishing finished"
        case "CANCELLED": "Cancelled"
        case "ON_HIATUS": "On hiatus"
        default: "Unknown"
        }
    }

    var statusSymbol: String {
        switch status {
        case "ONGOING": "clock"
        case "COMPLETED", "PUBLISHING_FINISHED": "checkmark.circle"
        case "LICENSED": "lock"
        case "CANCELLED": "xmark.circle"
        case "ON_HIATUS": "pause.circle"
        default: "questionmark.circle"
        }
    }

    static let cardFields = "id title thumbnailUrl inLibrary"

    static let libraryFields = """
    id title thumbnailUrl inLibrary inLibraryAt status sourceId unreadCount bookmarkCount
    chapters { totalCount }
    lastReadChapter { lastReadAt }
    latestUploadedChapter { uploadDate }
    latestFetchedChapter { fetchedAt }
    categories { nodes { id } }
    """

    static let detailFields = """
    id title thumbnailUrl inLibrary author artist description genre status realUrl sourceId unreadCount
    source { id displayName }
    categories { nodes { id } }
    """
}

struct Chapter: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var chapterNumber: Double
    var scanlator: String?
    var uploadDate: String
    var fetchedAt: String?
    var isRead: Bool
    var isBookmarked: Bool
    var lastPageRead: Int
    var pageCount: Int
    var sourceOrder: Int
    var lastReadAt: String
    var mangaId: Int
    var realUrl: String?
    var manga: MangaRef?

    struct MangaRef: Codable, Hashable {
        var id: Int
        var title: String
        var thumbnailUrl: String?
    }

    var uploaded: Date? { Date(milliseconds: uploadDate) }
    var fetched: Date? { Date(seconds: fetchedAt) }
    var lastRead: Date? { Date(seconds: lastReadAt) }
    /// Saved on this phone.
    var isDownloaded: Bool { Downloads.shared.has(id) }

    static let fields = """
    id name chapterNumber scanlator uploadDate fetchedAt isRead isBookmarked lastPageRead pageCount
    sourceOrder lastReadAt mangaId realUrl
    """

    static let fieldsWithManga = fields + " manga { id title thumbnailUrl }"
}

struct Category: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var order: Int
}

struct Source: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var lang: String
    var iconUrl: String
    var supportsLatest: Bool

    var isLocal: Bool { id == "0" }

    static let fields = "id name lang iconUrl supportsLatest"
}

struct Extension: Codable, Identifiable, Hashable {
    var pkgName: String
    var name: String
    var lang: String
    var versionName: String
    var iconUrl: String
    var isInstalled: Bool
    var hasUpdate: Bool
    var isObsolete: Bool
    var contentWarning: String

    var id: String { pkgName }
    var isAdult: Bool { contentWarning == "NSFW" }

    static let fields = "pkgName name lang versionName iconUrl isInstalled hasUpdate isObsolete contentWarning"
}

struct ExtensionStore: Codable, Identifiable, Hashable {
    var name: String
    var indexUrl: String

    var id: String { indexUrl }
}

struct UpdateJobs: Codable, Hashable {
    var isRunning: Bool
    var totalJobs: Int
    var finishedJobs: Int
}

struct AboutServer: Codable, Hashable {
    var name: String
    var version: String
    var buildType: String
}

extension Date {
    /// The server writes most times as seconds in a string, with "0" for never.
    init?(seconds text: String?) {
        guard let text, let value = Double(text), value > 0 else { return nil }
        self.init(timeIntervalSince1970: value)
    }

    init?(milliseconds text: String?) {
        guard let text, let value = Double(text), value > 0 else { return nil }
        self.init(timeIntervalSince1970: value / 1000)
    }
}

enum Lang {
    /// "en" → "English", and the two the extension index makes up for itself.
    static func name(_ code: String) -> String {
        switch code {
        case "all": return "Multi"
        case "localsourcelang": return "Other"
        default: return Locale.current.localizedString(forIdentifier: code)?.capitalized(with: .current) ?? code.uppercased()
        }
    }
}
