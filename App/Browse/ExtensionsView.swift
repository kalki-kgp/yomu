import SwiftUI

struct ExtensionsList: View {
    let search: String

    @Environment(AppModel.self) private var app
    @State private var extensions: [Extension] = []
    @State private var loaded = false
    @State private var problem: String?
    @State private var busy: Set<String> = []
    @State private var languages = Stored.set(Keys.extensionLanguages)
    @State private var showLanguages = false

    /// Until someone picks, show the phone's language, anything already installed, and multi.
    private var enabled: Set<String> {
        if let languages { return languages }
        var result: Set<String> = ["all"]
        if let code = Locale.current.language.languageCode?.identifier { result.insert(code) }
        result.formUnion(extensions.filter(\.isInstalled).map(\.lang))
        return result
    }

    private var groups: [(title: String, items: [Extension])] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let pool = extensions.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        var result: [(String, [Extension])] = []
        let updates = pool.filter { $0.isInstalled && $0.hasUpdate }
        if !updates.isEmpty { result.append(("Updates pending", updates)) }
        let installed = pool.filter { $0.isInstalled && !$0.hasUpdate }
        if !installed.isEmpty { result.append(("Installed", installed)) }
        let enabled = enabled
        let available = Dictionary(grouping: pool.filter { !$0.isInstalled && enabled.contains($0.lang) }, by: \.lang)
        for lang in available.keys.sorted(by: { Lang.name($0) < Lang.name($1) }) {
            result.append((Lang.name(lang), available[lang] ?? []))
        }
        return result
    }

    var body: some View {
        List {
            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(group.items) { item in
                        row(item)
                    }
                } header: {
                    HStack {
                        Text(verbatim: group.title)
                        Spacer()
                        if group.title == "Updates pending" {
                            Button("Update all") {
                                for item in group.items { change(item, .update) }
                            }
                            .font(.footnote.weight(.semibold))
                        }
                    }
                }
            }
        }
        .overlay {
            if let problem {
                Failed(message: problem) { Task { await load(reload: false) } }
            } else if !loaded {
                ProgressView()
            } else if extensions.isEmpty {
                ContentUnavailableView("No extensions", systemImage: "puzzlepiece.extension",
                                       description: Text("Add a repo under More, Settings, Extension repos."))
            }
        }
        .refreshable { await load(reload: true) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Languages", systemImage: "globe") { showLanguages = true }
            }
        }
        .sheet(isPresented: $showLanguages) {
            LanguagePicker(all: Set(extensions.map(\.lang)), chosen: enabled) { picked in
                languages = picked
                Stored.save(picked, Keys.extensionLanguages)
            }
        }
        .task { await load(reload: !loaded) }
    }

    private func row(_ item: Extension) -> some View {
        HStack(spacing: 12) {
            IconView(path: item.iconUrl)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: item.name).font(.body).lineLimit(1)
                HStack(spacing: 6) {
                    Text(verbatim: Lang.name(item.lang))
                    Text(verbatim: item.versionName)
                    if item.isAdult { Text("18+").foregroundStyle(.red) }
                    if item.isObsolete { Text("Obsolete").foregroundStyle(.red) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if busy.contains(item.pkgName) {
                ProgressView()
            } else if item.isInstalled {
                if item.hasUpdate {
                    Button("Update") { change(item, .update) }.buttonStyle(.glassProminent)
                }
                Menu {
                    Button("Uninstall", systemImage: "trash", role: .destructive) { change(item, .uninstall) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 30, height: 30)
                }
                .foregroundStyle(.secondary)
            } else {
                Button("Install") { change(item, .install) }.buttonStyle(.glass)
            }
        }
        .font(.subheadline.weight(.medium))
    }

    private func change(_ item: Extension, _ change: API.ExtensionChange) {
        busy.insert(item.pkgName)
        Task {
            do {
                try await API.change(extension: item.pkgName, change)
            } catch {
                problem = nil
            }
            await load(reload: false)
            busy.remove(item.pkgName)
            app.revision += 1
            await app.refreshBadges()
        }
    }

    private func load(reload: Bool) async {
        do {
            if reload { try? await API.reloadExtensions() }
            extensions = try await API.extensions().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            problem = nil
        } catch is CancellationError {
        } catch {
            if !loaded { problem = error.localizedDescription }
        }
        loaded = true
    }
}

struct LanguagePicker: View {
    let all: Set<String>
    let save: (Set<String>) -> Void

    @State private var chosen: Set<String>
    @Environment(\.dismiss) private var dismiss

    init(all: Set<String>, chosen: Set<String>, save: @escaping (Set<String>) -> Void) {
        self.all = all
        self.save = save
        _chosen = State(initialValue: chosen)
    }

    var body: some View {
        NavigationStack {
            List(all.sorted { Lang.name($0) < Lang.name($1) }, id: \.self) { code in
                Toggle(Lang.name(code), isOn: .init(
                    get: { chosen.contains(code) },
                    set: { if $0 { chosen.insert(code) } else { chosen.remove(code) } }))
            }
            .navigationTitle("Languages")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        save(chosen)
                        dismiss()
                    }
                }
            }
        }
    }
}
