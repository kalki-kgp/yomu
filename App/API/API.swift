// Every call the app makes, one function each.

import Foundation

enum API {
    private struct Empty: Decodable {}

    // MARK: Server

    static func about(at base: URL? = nil, login: Login? = nil) async throws -> AboutServer {
        struct R: Decodable { let aboutServer: AboutServer }
        let r: R = try await GQL.run("{ aboutServer { name version buildType } }", at: base, login: login)
        return r.aboutServer
    }

    // MARK: Library

    static func library() async throws -> [Manga] {
        struct R: Decodable { let mangas: Nodes<Manga> }
        let result = try await Offline.cached("library") {
            let r: R = try await GQL.run("{ mangas(condition: {inLibrary: true}) { nodes { \(Manga.libraryFields) } } }")
            return r.mangas.nodes
        }
        if result.fresh {
            Offline.libraryIDs = Set(result.value.map(\.id))
            let covers = result.value.compactMap { Server.shared.url($0.thumbnailUrl) }
            Task.detached(priority: .utility) {
                for cover in covers { await ImageStore.shared.keep(cover) }
            }
        }
        return result.value
    }

    static func categories() async throws -> [Category] {
        struct R: Decodable { let categories: Nodes<Category> }
        return try await Offline.cached("categories") {
            let r: R = try await GQL.run("{ categories(order: [{by: ORDER}]) { nodes { id name order } } }")
            return r.categories.nodes
        }.value
    }

    static func updateLibrary(category: Int? = nil) async throws {
        let _: Empty = try await GQL.run(
            "mutation($categories: [Int!]) { updateLibrary(input: {categories: $categories}) { clientMutationId } }",
            ["categories": category.map { [$0] as Any } ?? NSNull()])
    }

    static func updateJobs() async throws -> UpdateJobs {
        struct R: Decodable { let libraryUpdateStatus: Status }
        struct Status: Decodable { let jobsInfo: UpdateJobs }
        let r: R = try await GQL.run("{ libraryUpdateStatus { jobsInfo { isRunning totalJobs finishedJobs } } }")
        return r.libraryUpdateStatus.jobsInfo
    }

    static func setInLibrary(_ ids: [Int], _ value: Bool) async throws {
        let _: Empty = try await GQL.run(
            "mutation($ids: [Int!]!, $value: Boolean!) { updateMangas(input: {ids: $ids, patch: {inLibrary: $value}}) { clientMutationId } }",
            ["ids": ids, "value": value])
        if value {
            Offline.libraryIDs.formUnion(ids)
            Task.detached(priority: .utility) {
                for id in ids { await Offline.keep(manga: id) }
            }
        } else {
            Offline.libraryIDs.subtract(ids)
            for id in ids { Offline.forget(manga: id) }
        }
        // The phone's copy of the library should match without waiting for the Library tab.
        Task.detached(priority: .utility) { _ = try? await library() }
    }

    static func setCategories(manga id: Int, to categories: [Int]) async throws {
        let _: Empty = try await GQL.run(
            """
            mutation($id: Int!, $add: [Int!]) {
              updateMangaCategories(input: {id: $id, patch: {clearCategories: true, addToCategories: $add}}) { clientMutationId }
            }
            """,
            ["id": id, "add": categories])
    }

    static func createCategory(_ name: String) async throws {
        let _: Empty = try await GQL.run(
            "mutation($name: String!) { createCategory(input: {name: $name}) { clientMutationId } }", ["name": name])
    }

    static func renameCategory(_ id: Int, to name: String) async throws {
        let _: Empty = try await GQL.run(
            "mutation($id: Int!, $name: String!) { updateCategory(input: {id: $id, patch: {name: $name}}) { clientMutationId } }",
            ["id": id, "name": name])
    }

    static func deleteCategory(_ id: Int) async throws {
        let _: Empty = try await GQL.run(
            "mutation($id: Int!) { deleteCategory(input: {categoryId: $id}) { clientMutationId } }", ["id": id])
    }

    static func moveCategory(_ id: Int, to position: Int) async throws {
        let _: Empty = try await GQL.run(
            "mutation($id: Int!, $position: Int!) { updateCategoryOrder(input: {id: $id, position: $position}) { clientMutationId } }",
            ["id": id, "position": position])
    }

    // MARK: Manga and chapters

    static func manga(_ id: Int) async throws -> Manga {
        struct R: Decodable { let manga: Manga }
        return try await Offline.cached("manga-\(id)", save: { $0.isInLibrary || Offline.keeps(id) }) {
            let r: R = try await GQL.run("query($id: Int!) { manga(id: $id) { \(Manga.detailFields) } }", ["id": id])
            return r.manga
        }.value
    }

    /// Newest first, with anything marked on the phone laid over what the server has.
    static func chapters(of id: Int) async throws -> [Chapter] {
        struct R: Decodable { let chapters: Nodes<Chapter> }
        await Marks.shared.sync()
        let result = try await Offline.cached("chapters-\(id)", save: { _ in Offline.keeps(id) }) {
            let r: R = try await GQL.run(
                "query($id: Int!) { chapters(condition: {mangaId: $id}, order: [{by: SOURCE_ORDER, byType: DESC}]) { nodes { \(Chapter.fields) } } }",
                ["id": id])
            return r.chapters.nodes
        }
        var chapters = result.value
        Marks.shared.apply(to: &chapters, fresh: result.fresh)
        return chapters
    }

    /// Asks the source again, which is slow, and saves what comes back.
    static func refresh(manga id: Int) async throws -> (Manga, [Chapter]) {
        struct R: Decodable { let fetchMangaAndChapters: Payload }
        struct Payload: Decodable { let manga: Manga; let chapters: [Chapter] }
        await Marks.shared.sync()
        let r: R = try await GQL.run(
            """
            mutation($id: Int!) {
              fetchMangaAndChapters(input: {id: $id, fetchManga: true, fetchChapters: true}) {
                manga { \(Manga.detailFields) }
                chapters { \(Chapter.fields) }
              }
            }
            """, ["id": id])
        var chapters = r.fetchMangaAndChapters.chapters.sorted { $0.sourceOrder > $1.sourceOrder }
        if Offline.keeps(id) {
            Offline.write("manga-\(id)", r.fetchMangaAndChapters.manga)
            Offline.write("chapters-\(id)", chapters)
        }
        Marks.shared.apply(to: &chapters, fresh: true)
        return (r.fetchMangaAndChapters.manga, chapters)
    }

    /// Notes the change on the phone, then sends it if the server is there. With no server it
    /// waits and goes out with the next sync.
    static func update(chapters ids: [Int], read: Bool? = nil, bookmarked: Bool? = nil, lastPage: Int? = nil) async throws {
        guard !ids.isEmpty else { return }
        Marks.shared.record(ids, read: read, bookmarked: bookmarked, lastPage: lastPage)
        await Marks.shared.sync()
    }

    static func send(chapters ids: [Int], read: Bool?, bookmarked: Bool?, lastPage: Int?) async throws {
        var patch: [String: Any] = [:]
        if let read { patch["isRead"] = read }
        if let bookmarked { patch["isBookmarked"] = bookmarked }
        if let lastPage { patch["lastPageRead"] = lastPage }
        let _: Empty = try await GQL.run(
            "mutation($ids: [Int!]!, $patch: UpdateChapterPatchInput!) { updateChapters(input: {ids: $ids, patch: $patch}) { clientMutationId } }",
            ["ids": ids, "patch": patch])
    }

    /// Pages from the phone if the chapter is saved there, from the server otherwise.
    static func pages(of chapter: Int) async throws -> [String] {
        if let saved = Downloads.shared.pages(of: chapter) { return saved }
        return try await remotePages(of: chapter)
    }

    static func remotePages(of chapter: Int) async throws -> [String] {
        struct R: Decodable { let fetchChapterPages: Payload }
        struct Payload: Decodable { let pages: [String] }
        let r: R = try await GQL.run(
            "mutation($id: Int!) { fetchChapterPages(input: {chapterId: $id}) { pages } }", ["id": chapter])
        return r.fetchChapterPages.pages
    }

    // MARK: Updates and history

    /// Chapters that arrived after their series was added, newest first. Adding a series fetches
    /// its whole back catalogue, and none of that is news.
    static func updates() async throws -> [Chapter] {
        var chapters = try await Offline.cached("updates") { try await remoteUpdates() }.value
        Marks.shared.apply(to: &chapters, fresh: false)
        return chapters
    }

    private static func remoteUpdates() async throws -> [Chapter] {
        struct Library: Decodable { let mangas: Nodes<Entry> }
        struct Entry: Codable, Hashable { let id: Int; let inLibraryAt: String }
        let library: Library = try await GQL.run("{ mangas(condition: {inLibrary: true}) { nodes { id inLibraryAt } } }")
        guard !library.mangas.nodes.isEmpty else { return [] }
        let clauses = library.mangas.nodes.map { entry -> [String: Any] in
            ["mangaId": ["equalTo": entry.id], "fetchedAt": ["greaterThan": entry.inLibraryAt]]
        }
        struct R: Decodable { let chapters: Nodes<Chapter> }
        let r: R = try await GQL.run(
            """
            query($filter: ChapterFilterInput) {
              chapters(filter: $filter, order: [{by: FETCHED_AT, byType: DESC}, {by: SOURCE_ORDER, byType: DESC}], first: 300) {
                nodes { \(Chapter.fieldsWithManga) }
              }
            }
            """, ["filter": ["or": clauses]])
        return r.chapters.nodes
    }

    static func history() async throws -> [Chapter] {
        struct R: Decodable { let chapters: Nodes<Chapter> }
        await Marks.shared.sync()
        var chapters = try await Offline.cached("history") {
            let r: R = try await GQL.run(
                """
                { chapters(filter: {lastReadAt: {greaterThan: "0"}}, order: [{by: LAST_READ_AT, byType: DESC}], first: 500) {
                    nodes { \(Chapter.fieldsWithManga) }
                } }
                """)
            return r.chapters.nodes
        }.value
        Marks.shared.apply(to: &chapters, fresh: false)
        return chapters
    }

    // MARK: Sources and extensions

    static func sources() async throws -> [Source] {
        struct R: Decodable { let sources: Nodes<Source> }
        return try await Offline.cached("sources") {
            let r: R = try await GQL.run("{ sources { nodes { \(Source.fields) } } }")
            return r.sources.nodes
        }.value
    }

    enum Listing: String {
        case popular = "POPULAR", latest = "LATEST", search = "SEARCH"
    }

    static func browse(source: String, _ listing: Listing, page: Int, query: String? = nil) async throws -> (mangas: [Manga], more: Bool) {
        struct R: Decodable { let fetchSourceManga: Payload }
        struct Payload: Decodable { let hasNextPage: Bool; let mangas: [Manga] }
        var input: [String: Any] = ["source": source, "type": listing.rawValue, "page": page]
        if let query { input["query"] = query }
        let r: R = try await GQL.run(
            "mutation($input: FetchSourceMangaInput!) { fetchSourceManga(input: $input) { hasNextPage mangas { \(Manga.cardFields) } } }",
            ["input": input])
        return (r.fetchSourceManga.mangas, r.fetchSourceManga.hasNextPage)
    }

    static func extensions() async throws -> [Extension] {
        struct R: Decodable { let extensions: Nodes<Extension> }
        let r: R = try await GQL.run("{ extensions { nodes { \(Extension.fields) } } }")
        return r.extensions.nodes
    }

    /// Pulls the index from every repo again.
    static func reloadExtensions() async throws {
        let _: Empty = try await GQL.run("mutation { fetchExtensions(input: {}) { clientMutationId } }")
    }

    static func extensionUpdates() async throws -> Int {
        struct R: Decodable { let extensions: Count }
        let r: R = try await GQL.run("{ extensions(condition: {hasUpdate: true}) { totalCount } }")
        return r.extensions.totalCount
    }

    enum ExtensionChange: String {
        case install, update, uninstall
    }

    static func change(extension pkg: String, _ change: ExtensionChange) async throws {
        let _: Empty = try await GQL.run(
            "mutation($id: String!, $patch: UpdateExtensionPatchInput!) { updateExtension(input: {id: $id, patch: $patch}) { clientMutationId } }",
            ["id": pkg, "patch": [change.rawValue: true]])
    }

    static func stores() async throws -> [ExtensionStore] {
        struct R: Decodable { let extensionStores: Nodes<ExtensionStore> }
        let r: R = try await GQL.run("{ extensionStores { nodes { name indexUrl } } }")
        return r.extensionStores.nodes
    }

    static func addStore(_ url: String) async throws {
        let _: Empty = try await GQL.run(
            "mutation($url: String!) { addExtensionStore(input: {indexUrl: $url}) { clientMutationId } }", ["url": url])
    }

    static func removeStore(_ url: String) async throws {
        let _: Empty = try await GQL.run(
            "mutation($url: String!) { removeExtensionStore(input: {indexUrl: $url}) { clientMutationId } }", ["url": url])
    }
}
