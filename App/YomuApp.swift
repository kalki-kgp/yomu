import SwiftUI

@main
struct YomuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppModel()
    @State private var server = Server.shared
    @AppStorage(Keys.appearance) private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            Group {
                if server.base == nil {
                    ConnectView()
                } else {
                    RootView()
                }
            }
            .environment(app)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var phase

    var body: some View {
        TabView {
            Tab("Library", systemImage: "books.vertical.fill") {
                NavigationStack { LibraryView().routes() }
            }
            Tab("Updates", systemImage: "bell.fill") {
                NavigationStack { UpdatesView().routes() }
            }
            Tab("History", systemImage: "clock.arrow.circlepath") {
                NavigationStack { HistoryView().routes() }
            }
            Tab("Browse", systemImage: "safari.fill") {
                NavigationStack { BrowseView().routes() }
            }
            .badge(app.extensionUpdates)
            Tab("More", systemImage: "ellipsis") {
                NavigationStack { MoreView().routes() }
            }
        }
        .minimizingTabBar()
        .overlay {
            if let request = app.reading {
                ReaderHost(request: request)
                    .id(request.id)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.snappy(duration: 0.32), value: app.reading?.id)
        .task(id: phase) {
            guard phase == .active else { return }
            #if DEBUG
            // `YOMU_OPEN=<manga id>:<chapter id>` opens the reader at launch, for checking it in the simulator.
            if app.reading == nil, let ids = ProcessInfo.processInfo.environment["YOMU_OPEN"]?.split(separator: ":").compactMap({ Int($0) }), ids.count == 2 {
                app.reading = ReaderRequest(manga: ids[0], chapter: ids[1])
            }
            #endif
            Downloads.shared.retry()
            await Marks.shared.sync()
            await app.refreshBadges()
            await Offline.refresh()
        }
    }
}

/// First launch, and whenever the server address is cleared.
struct ConnectView: View {
    @State private var text = ""
    @State private var username = ""
    @State private var password = ""
    @State private var wantsLogin = false
    @State private var checking = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("192.168.1.3:4567", text: $text)
                        .addressField()
                        .onSubmit(connect)
                } header: {
                    Text("Suwayomi server")
                } footer: {
                    if let problem, !wantsLogin { Text(verbatim: problem).foregroundStyle(.red) }
                }
                if wantsLogin {
                    Section {
                        TextField("Username", text: $username).plainField()
                        SecureField("Password", text: $password).onSubmit(connect)
                    } header: {
                        Text("Login")
                    } footer: {
                        if let problem { Text(verbatim: problem).foregroundStyle(.red) }
                    }
                }
                Section {
                    Button(action: connect) {
                        HStack {
                            Text("Connect")
                            if checking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(checking || Server.address(from: text) == nil || (wantsLogin && (username.isEmpty || password.isEmpty)))
                }
            }
            .navigationTitle("Yomu")
        }
    }

    private func connect() {
        guard let url = Server.address(from: text) else { return }
        checking = true
        problem = nil
        Task {
            let login = wantsLogin ? Login(username: username, password: password) : nil
            do {
                _ = try await API.about(at: url, login: login)
                Server.shared.use(url, login: login)
            } catch is LoginNeeded {
                // The first 401 just means "ask"; a second means the details were wrong.
                if wantsLogin { problem = LoginNeeded().localizedDescription }
                wantsLogin = true
            } catch {
                problem = error.localizedDescription
            }
            checking = false
        }
    }
}
