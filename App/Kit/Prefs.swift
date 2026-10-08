// Choices that live on the phone: how the library is shown, how each series is read.

import SwiftUI

enum Keys {
    static let appearance = "appearance"
    static let libraryDisplay = "library.display"
    static let librarySort = "library.sort"
    static let libraryAscending = "library.ascending"
    static let libraryColumns = "library.columns"
    static let libraryCategory = "library.category"
    static let unreadBadge = "library.unreadBadge"
    static let downloadBadge = "library.downloadBadge"
    static let filterDownloaded = "library.filter.downloaded"
    static let filterUnread = "library.filter.unread"
    static let filterStarted = "library.filter.started"
    static let filterBookmarked = "library.filter.bookmarked"
    static let filterCompleted = "library.filter.completed"
    static let downloadedOnly = "downloadedOnly"
    static let incognito = "incognito"
    static let readingMode = "reader.mode"
    static let showPageNumber = "reader.pageNumber"
    static let keepAwake = "reader.keepAwake"
    static let readerTheme = "reader.theme"
    static let fullscreen = "reader.fullscreen"
    static let longTap = "reader.longTap"
    static let alwaysTransition = "reader.alwaysTransition"
    static let pageTransitions = "reader.pageTransitions"
    static let rotation = "reader.rotation"
    static let pagerTaps = "reader.pager.taps"
    static let pagerInvert = "reader.pager.invert"
    static let stripTaps = "reader.strip.taps"
    static let stripInvert = "reader.strip.invert"
    static let scaleType = "reader.scaleType"
    static let zoomStart = "reader.zoomStart"
    static let cropPaged = "reader.pager.crop"
    static let cropStrip = "reader.strip.crop"
    static let stripPadding = "reader.strip.padding"
    static let customBrightness = "reader.brightness.on"
    static let brightnessValue = "reader.brightness.value"
    static let colorFilter = "reader.filter.on"
    static let filterRed = "reader.filter.red"
    static let filterGreen = "reader.filter.green"
    static let filterBlue = "reader.filter.blue"
    static let filterAlpha = "reader.filter.alpha"
    static let filterBlend = "reader.filter.blend"
    static let grayscale = "reader.grayscale"
    static let inverted = "reader.inverted"
    static let chapterSort = "chapters.sort"
    static let chapterAscending = "chapters.ascending"
    static let chapterUnread = "chapters.filter.unread"
    static let chapterDownloaded = "chapters.filter.downloaded"
    static let chapterBookmarked = "chapters.filter.bookmarked"
    static let extensionLanguages = "extensions.languages"
    static let pinnedSources = "sources.pinned"
    static let lastSource = "sources.last"
}

/// Off, must have, must not have: the three-way filter Mihon uses everywhere.
enum Tri: Int {
    case off, include, exclude

    var next: Tri { Tri(rawValue: (rawValue + 1) % 3) ?? .off }

    func allows(_ value: Bool) -> Bool {
        switch self {
        case .off: true
        case .include: value
        case .exclude: !value
        }
    }
}

enum LibraryDisplay: String, CaseIterable, Identifiable {
    case compact, comfortable, coverOnly, list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact grid"
        case .comfortable: "Comfortable grid"
        case .coverOnly: "Cover-only grid"
        case .list: "List"
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case alphabetical, totalChapters, lastRead, unreadCount, latestChapter, chapterFetchDate, dateAdded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alphabetical: "Alphabetically"
        case .totalChapters: "Total chapters"
        case .lastRead: "Last read"
        case .unreadCount: "Unread count"
        case .latestChapter: "Latest chapter"
        case .chapterFetchDate: "Chapter fetch date"
        case .dateAdded: "Date added"
        }
    }

    func ordered(_ a: Manga, before b: Manga) -> Bool {
        func stamp(_ text: String?) -> Double { text.flatMap(Double.init) ?? 0 }
        switch self {
        case .alphabetical: return a.title.localizedStandardCompare(b.title) == .orderedAscending
        case .totalChapters: return a.total < b.total
        case .lastRead: return stamp(a.lastReadChapter?.lastReadAt) < stamp(b.lastReadChapter?.lastReadAt)
        case .unreadCount: return a.unread < b.unread
        case .latestChapter: return stamp(a.latestUploadedChapter?.uploadDate) < stamp(b.latestUploadedChapter?.uploadDate)
        case .chapterFetchDate: return stamp(a.latestFetchedChapter?.fetchedAt) < stamp(b.latestFetchedChapter?.fetchedAt)
        case .dateAdded: return stamp(a.inLibraryAt) < stamp(b.inLibraryAt)
        }
    }
}

enum ChapterSort: String, CaseIterable, Identifiable {
    case source, number, uploadDate, alphabetical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source: "By source"
        case .number: "By chapter number"
        case .uploadDate: "By upload date"
        case .alphabetical: "Alphabetically"
        }
    }

    func ordered(_ a: Chapter, before b: Chapter) -> Bool {
        switch self {
        case .source: a.sourceOrder < b.sourceOrder
        case .number: a.chapterNumber < b.chapterNumber
        case .uploadDate: (Double(a.uploadDate) ?? 0) < (Double(b.uploadDate) ?? 0)
        case .alphabetical: a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

enum ReadingMode: String, CaseIterable, Identifiable {
    case rtl, ltr, vertical, webtoon, strip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rtl: "Paged (right to left)"
        case .ltr: "Paged (left to right)"
        case .vertical: "Paged (vertical)"
        case .webtoon: "Long strip"
        case .strip: "Long strip with gaps"
        }
    }

    var symbol: String {
        switch self {
        case .rtl: "arrow.left.square"
        case .ltr: "arrow.right.square"
        case .vertical: "arrow.down.square"
        case .webtoon: "rectangle.arrowtriangle.2.inward"
        case .strip: "rectangle.split.1x2"
        }
    }

    var isPaged: Bool { self == .rtl || self == .ltr || self == .vertical }

    /// The mode for everything that hasn't been given its own.
    static var standard: ReadingMode {
        UserDefaults.standard.string(forKey: Keys.readingMode).flatMap(ReadingMode.init) ?? .rtl
    }

    static func saved(for manga: Int) -> ReadingMode? {
        UserDefaults.standard.string(forKey: "reader.mode.\(manga)").flatMap(ReadingMode.init)
    }

    static func save(_ mode: ReadingMode?, for manga: Int) {
        UserDefaults.standard.set(mode?.rawValue, forKey: "reader.mode.\(manga)")
    }
}

// MARK: - Reader settings, the same ones as Mihon's reader sheet

enum ReaderTheme: String, CaseIterable, Identifiable {
    case black, gray, white, automatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: "Black"
        case .gray: "Gray"
        case .white: "White"
        case .automatic: "Automatic"
        }
    }

    func color(system: ColorScheme) -> Color {
        switch self {
        case .black: .black
        case .gray: Color(white: 0.13)
        case .white: .white
        case .automatic: system == .dark ? .black : .white
        }
    }

    /// The menus and chapter cards follow the page background.
    func scheme(system: ColorScheme) -> ColorScheme {
        switch self {
        case .black, .gray: .dark
        case .white: .light
        case .automatic: system
        }
    }
}

enum ReaderRotation: String, CaseIterable, Identifiable {
    case free, portrait, landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: "Free"
        case .portrait: "Locked portrait"
        case .landscape: "Locked landscape"
        }
    }

    var symbol: String {
        switch self {
        case .free: "rotate.right"
        case .portrait: "rectangle.portrait"
        case .landscape: "rectangle"
        }
    }

    static var standard: ReaderRotation {
        UserDefaults.standard.string(forKey: Keys.rotation).flatMap(ReaderRotation.init) ?? .free
    }

    static func saved(for manga: Int) -> ReaderRotation? {
        UserDefaults.standard.string(forKey: "reader.rotation.\(manga)").flatMap(ReaderRotation.init)
    }

    static func save(_ rotation: ReaderRotation?, for manga: Int) {
        UserDefaults.standard.set(rotation?.rawValue, forKey: "reader.rotation.\(manga)")
    }
}

enum TapAction {
    case menu, previous, next, left, right
}

enum TapInvert: String, CaseIterable, Identifiable {
    case none, horizontal, vertical, both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        case .both: "Both"
        }
    }
}

/// Where on the screen a tap turns the page, and which way.
enum TapLayout: String, CaseIterable, Identifiable {
    case standard, lShaped, kindle, edge, rightLeft, disabled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Default"
        case .lShaped: "L-shaped"
        case .kindle: "Kindle-ish"
        case .edge: "Edge"
        case .rightLeft: "Right and left"
        case .disabled: "Disabled"
        }
    }

    /// `point` is in unit coordinates, (0, 0) at the top left of the screen.
    func action(at point: CGPoint, invert: TapInvert, paged: Bool) -> TapAction {
        var x = point.x
        var y = point.y
        if invert == .horizontal || invert == .both { x = 1 - x }
        if invert == .vertical || invert == .both { y = 1 - y }
        let third = 1.0 / 3
        switch self == .standard ? (paged ? .rightLeft : .lShaped) : self {
        case .lShaped:
            if y < third { return .previous }
            if y > 2 * third { return .next }
            if x < third { return .previous }
            if x > 2 * third { return .next }
            return .menu
        case .kindle:
            if y < third { return .menu }
            return x < third ? .previous : .next
        case .edge:
            if x < third || x > 2 * third { return .next }
            return y > 2 * third ? .previous : .menu
        case .rightLeft:
            if x < third { return .left }
            if x > 2 * third { return .right }
            return .menu
        case .standard, .disabled:
            return .menu
        }
    }
}

enum ScaleType: String, CaseIterable, Identifiable {
    case fitScreen, stretch, fitWidth, fitHeight, original, smart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fitScreen: "Fit screen"
        case .stretch: "Stretch"
        case .fitWidth: "Fit width"
        case .fitHeight: "Fit height"
        case .original: "Original size"
        case .smart: "Smart fit"
        }
    }
}

enum ZoomStart: String, CaseIterable, Identifiable {
    case automatic, left, right, center

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .left: "Left"
        case .right: "Right"
        case .center: "Center"
        }
    }

    /// Automatic starts where reading starts: the right edge for right-to-left, the left otherwise.
    func resolved(for mode: ReadingMode) -> ZoomStart {
        self == .automatic ? (mode == .rtl ? .right : .left) : self
    }
}

enum FilterBlend: String, CaseIterable, Identifiable {
    case standard, multiply, screen, overlay, dodge, burn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Default"
        case .multiply: "Multiply"
        case .screen: "Screen"
        case .overlay: "Overlay"
        case .dodge: "Dodge / Lighten"
        case .burn: "Burn / Darken"
        }
    }

    var mode: BlendMode {
        switch self {
        case .standard: .normal
        case .multiply: .multiply
        case .screen: .screen
        case .overlay: .overlay
        case .dodge: .colorDodge
        case .burn: .colorBurn
        }
    }
}

/// A set of strings in UserDefaults, for pinned sources and extension languages.
enum Stored {
    static func set(_ key: String) -> Set<String>? {
        (UserDefaults.standard.array(forKey: key) as? [String]).map(Set.init)
    }

    static func save(_ value: Set<String>, _ key: String) {
        UserDefaults.standard.set(value.sorted(), forKey: key)
    }
}
