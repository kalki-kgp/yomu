import SwiftUI

struct ReaderView: View {
    let request: ReaderRequest
    let close: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var system
    @Environment(\.scenePhase) private var phase
    @State private var model: ReaderModel
    @State private var position = ScrollPosition(idType: ReaderItem.self)
    @State private var showMenu = false
    @State private var showSettings = false
    @State private var strip = StripGeometry()

    @AppStorage(Keys.readerTheme) private var theme = ReaderTheme.black
    @AppStorage(Keys.showPageNumber) private var showPageNumber = true
    @AppStorage(Keys.fullscreen) private var fullscreen = true
    @AppStorage(Keys.keepAwake) private var keepAwake = true
    @AppStorage(Keys.longTap) private var longTap = true
    @AppStorage(Keys.alwaysTransition) private var alwaysTransition = true
    @AppStorage(Keys.pageTransitions) private var pageTransitions = true
    @AppStorage(Keys.pagerTaps) private var pagerTaps = TapLayout.standard
    @AppStorage(Keys.pagerInvert) private var pagerInvert = TapInvert.none
    @AppStorage(Keys.stripTaps) private var stripTaps = TapLayout.standard
    @AppStorage(Keys.stripInvert) private var stripInvert = TapInvert.none
    @AppStorage(Keys.cropPaged) private var cropPaged = false
    @AppStorage(Keys.cropStrip) private var cropStrip = false
    @AppStorage(Keys.customBrightness) private var customBrightness = false
    @AppStorage(Keys.brightnessValue) private var brightnessValue = 0
    @AppStorage(Keys.colorFilter) private var colorFilter = false
    @AppStorage(Keys.filterRed) private var filterRed = 0
    @AppStorage(Keys.filterGreen) private var filterGreen = 0
    @AppStorage(Keys.filterBlue) private var filterBlue = 0
    @AppStorage(Keys.filterAlpha) private var filterAlpha = 0
    @AppStorage(Keys.filterBlend) private var filterBlend = FilterBlend.standard
    @AppStorage(Keys.grayscale) private var grayscale = false
    @AppStorage(Keys.inverted) private var inverted = false

    init(request: ReaderRequest, close: @escaping () -> Void) {
        self.request = request
        self.close = close
        _model = State(initialValue: ReaderModel(manga: request.manga))
    }

    private var ready: Bool { !model.loading && model.problem == nil }

    var body: some View {
        ZStack {
            theme.color(system: system).ignoresSafeArea()
            if model.loading {
                ProgressView().controlSize(.large)
            } else if let problem = model.problem {
                Failed(message: problem) {
                    Task { await open(model.chapter?.id ?? request.chapter) }
                }
            } else {
                pages
            }
        }
        .overlay(alignment: .bottom) {
            if showPageNumber, !showMenu, ready, case .page = model.current {
                Text(verbatim: "\(model.page + 1) / \(model.pages.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
                    .padding(.bottom, 2)
                    .allowsHitTesting(false)
            }
        }
        // The dimmer sits over the pages and under the menus, so the controls stay readable.
        .overlay {
            if customBrightness, brightnessValue < 0 {
                Color.black.opacity(Double(-brightnessValue) / 100).ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if showMenu || !ready { topBar.transition(.move(edge: .top).combined(with: .opacity)) }
        }
        .overlay(alignment: .bottom) {
            if showMenu, ready { bottomBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .environment(\.colorScheme, theme.scheme(system: system))
        .hidesStatusBar(fullscreen && !showMenu)
        .persistentSystemOverlays(showMenu ? .automatic : .hidden)
        .sheet(isPresented: $showSettings) {
            ReaderSettings(model: model)
        }
        .task { await open(request.chapter) }
        .onAppear {
            Platform.keepAwake(keepAwake)
            Platform.lock(model.rotation)
            applyBrightness()
        }
        .onChange(of: keepAwake) { Platform.keepAwake(keepAwake) }
        .onChange(of: model.rotation) { Platform.lock(model.rotation) }
        .onChange(of: customBrightness) { applyBrightness() }
        .onChange(of: brightnessValue) { applyBrightness() }
        .onChange(of: phase) { applyBrightness() }
        .onChange(of: model.session) {
            position = ScrollPosition(id: ReaderItem.page(model.start), anchor: .top)
        }
        .onChange(of: model.current) { skipCard() }
        .onDisappear {
            Platform.keepAwake(false)
            Platform.lock(.free)
            Platform.setBrightness(nil)
            Task {
                await model.flush()
                app.revision += 1
            }
        }
    }

    /// The pages, with the colour settings laid over them.
    private var pages: some View {
        Group {
            if model.mode.isPaged {
                PagedReader(model: model, position: $position, crop: cropPaged, tap: tapped, held: longTap ? held : nil)
            } else {
                StripReader(model: model, position: $position, geometry: $strip, crop: cropStrip, tap: tapped, held: longTap ? held : nil)
            }
        }
        .id(model.session)
        .grayscale(grayscale ? 1 : 0)
        .overlay {
            // White laid on with "difference" turns every colour into its opposite.
            if inverted {
                Color.white.blendMode(.difference).ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .overlay {
            if colorFilter {
                Color(red: Double(filterRed) / 255, green: Double(filterGreen) / 255, blue: Double(filterBlue) / 255)
                    .opacity(Double(filterAlpha) / 255)
                    .blendMode(filterBlend.mode)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }

    private func open(_ id: Int, atEnd: Bool = false) async {
        await model.open(id, atEnd: atEnd)
    }

    /// 1 to 100 sets the screen itself. Below zero the screen goes to its lowest and the dimmer
    /// in `body` darkens it further. Zero leaves the system's own brightness alone.
    private func applyBrightness() {
        guard customBrightness, phase == .active, brightnessValue != 0 else {
            Platform.setBrightness(nil)
            return
        }
        Platform.setBrightness(brightnessValue > 0 ? CGFloat(brightnessValue) / 100 : 0)
    }

    // MARK: Moving

    private func go(_ step: Int) {
        let items = model.items
        guard let index = items.firstIndex(of: model.current) else { return }
        let target = index + step
        if (target >= items.count || model.current == .after), step > 0 {
            if let next = model.next { Task { await open(next.id) } }
        } else if (target < 0 || model.current == .before), step < 0 {
            if let previous = model.previous { Task { await open(previous.id, atEnd: true) } }
        } else if model.mode.isPaged {
            if pageTransitions {
                withAnimation(.snappy(duration: 0.25)) { position.scrollTo(id: items[target]) }
            } else {
                position.scrollTo(id: items[target])
            }
        } else {
            let y = max(strip.offset + strip.height * 0.75 * CGFloat(step), 0)
            if pageTransitions {
                withAnimation(.snappy(duration: 0.3)) { position.scrollTo(y: y) }
            } else {
                position.scrollTo(y: y)
            }
        }
    }

    /// A tap somewhere on the page, in unit coordinates.
    private func tapped(_ point: CGPoint) {
        let paged = model.mode.isPaged
        let layout = paged ? pagerTaps : stripTaps
        let action = showMenu ? .menu : layout.action(at: point, invert: paged ? pagerInvert : stripInvert, paged: paged)
        switch action {
        case .menu: withAnimation(.snappy(duration: 0.2)) { showMenu.toggle() }
        case .next: go(1)
        case .previous: go(-1)
        // Left and right are sides of the screen, so right-to-left reading swaps what they do.
        case .left: go(model.mode == .rtl ? 1 : -1)
        case .right: go(model.mode == .rtl ? -1 : 1)
        }
    }

    private func held(_ image: CGImage) {
        Platform.share(image)
    }

    /// With "always show chapter transition" off, reaching a card goes straight to that chapter.
    private func skipCard() {
        guard !alwaysTransition, model.settled, !model.loading else { return }
        if model.current == .after, let next = model.next {
            Task { await open(next.id) }
        } else if model.current == .before, let previous = model.previous {
            Task { await open(previous.id, atEnd: true) }
        }
    }

    // MARK: Menus

    private var topBar: some View {
        GlassEffectContainer {
            HStack(spacing: 10) {
                round("Close", "xmark", close)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: model.manga?.title ?? " ").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(verbatim: model.chapter?.name ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .glassEffect(.regular, in: .capsule)
                if let chapter = model.chapter, !model.loading {
                    round("Bookmark", chapter.isBookmarked ? "bookmark.fill" : "bookmark") { model.toggleBookmark() }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var bottomBar: some View {
        GlassEffectContainer {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    round("Previous chapter", "backward.end.fill") {
                        if let previous = model.previous { Task { await open(previous.id) } }
                    }
                    .disabled(model.previous == nil)
                    HStack(spacing: 10) {
                        Text(verbatim: "\(model.page + 1)").frame(minWidth: 24)
                        Slider(value: .init(get: { Double(model.page) }, set: { value in
                            let target = ReaderItem.page(Int(value.rounded()))
                            model.arrived(target)
                            position.scrollTo(id: target, anchor: .top)
                        }), in: 0...Double(max(model.pages.count - 1, 1)), step: 1)
                        Text(verbatim: "\(model.pages.count)").frame(minWidth: 24)
                    }
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .glassEffect(.regular, in: .capsule)
                    round("Next chapter", "forward.end.fill") {
                        if let next = model.next { Task { await open(next.id) } }
                    }
                    .disabled(model.next == nil)
                }
                .environment(\.layoutDirection, model.mode == .rtl ? .rightToLeft : .leftToRight)
                HStack(spacing: 10) {
                    Menu {
                        Picker("Reading mode", selection: .init(get: { model.mode }, set: { model.use($0) })) {
                            ForEach(ReadingMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                    } label: {
                        Label(model.mode.title, systemImage: model.mode.symbol)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Menu {
                        Picker("Rotation", selection: .init(get: { model.rotation }, set: { model.use($0) })) {
                            ForEach(ReaderRotation.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                    } label: {
                        glyph(model.rotation.symbol)
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Rotation")
                    round("Crop borders", (model.mode.isPaged ? cropPaged : cropStrip) ? "crop" : "rectangle.dashed") {
                        if model.mode.isPaged { cropPaged.toggle() } else { cropStrip.toggle() }
                    }
                    round("Settings", "gearshape.fill") { showSettings = true }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func glyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: .circle)
    }

    private func round(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { glyph(symbol) }
            .foregroundStyle(.primary)
            .accessibilityLabel(title)
    }
}

// MARK: - The page that slides away

/// Holds the reader over the rest of the app. It comes in from the right, and dragging in from
/// the left edge moves it with the finger, showing the screen it was opened from underneath,
/// the way a pushed screen behaves everywhere else on the phone.
struct ReaderHost: View {
    let request: ReaderRequest

    @Environment(AppModel.self) private var app
    @State private var pull: CGFloat = {
        #if DEBUG
        // `YOMU_PULL=<points>` starts the page part-way through the swipe, for a simulator screenshot.
        if let points = ProcessInfo.processInfo.environment["YOMU_PULL"].flatMap(Double.init) { return CGFloat(points) }
        #endif
        return 0
    }()
    @State private var leaving = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .leading) {
                // The screen behind lightens as more of it shows.
                Color.black.opacity(0.35 * (1 - pull / width)).ignoresSafeArea().allowsHitTesting(false)
                ReaderView(request: request) { leave(width) }
                    .background {
                        Rectangle().fill(.black).shadow(color: .black.opacity(0.4), radius: 14, x: -4).ignoresSafeArea()
                    }
                    .offset(x: pull)
                Color.clear
                    .frame(width: 20)
                    .contentShape(.rect)
                    .ignoresSafeArea()
                    .gesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .global)
                            .onChanged { drag in
                                guard !leaving else { return }
                                pull = max(drag.translation.width, 0)
                            }
                            .onEnded { drag in
                                // Far enough, or flicked fast enough, finishes the swipe; otherwise it settles back.
                                if drag.translation.width > width * 0.35 || drag.predictedEndTranslation.width > width * 0.7 {
                                    leave(width)
                                } else {
                                    withAnimation(.snappy(duration: 0.25)) { pull = 0 }
                                }
                            }
                    )
            }
        }
    }

    private func leave(_ width: CGFloat) {
        guard !leaving else { return }
        leaving = true
        withAnimation(.snappy(duration: 0.28)) {
            pull = width
        } completion: {
            app.reading = nil
        }
    }
}

// MARK: - Paged

struct PagedReader: View {
    let model: ReaderModel
    @Binding var position: ScrollPosition
    let crop: Bool
    let tap: (CGPoint) -> Void
    let held: ((CGImage) -> Void)?

    @AppStorage(Keys.scaleType) private var scale = ScaleType.fitScreen
    @AppStorage(Keys.zoomStart) private var zoomStart = ZoomStart.automatic

    var body: some View {
        let vertical = model.mode == .vertical
        ScrollView(vertical ? .vertical : .horizontal) {
            // The target layout has to sit on the stack itself; on a wrapper around the two
            // branches, jumping to a page and reporting the page in view both quietly stop working.
            if vertical {
                LazyVStack(spacing: 0) { cells }.scrollTargetLayout()
            } else {
                LazyHStack(spacing: 0) { cells }.scrollTargetLayout()
            }
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .onScrollTargetVisibilityChange(idType: ReaderItem.self, threshold: 0.6) { visible in
            if let item = visible.first { model.arrived(item) }
        }
        .environment(\.layoutDirection, model.mode == .rtl ? .rightToLeft : .leftToRight)
        .ignoresSafeArea()
    }

    private var cells: some View {
        ForEach(model.items, id: \.self) { item in
            Group {
                switch item {
                case .page(let number):
                    PageCell(path: model.pages[number], crop: crop, scale: scale,
                             start: zoomStart.resolved(for: model.mode), tap: tap, held: held)
                case .before, .after:
                    ChapterCard(model: model, item: item).background { TapArea(tap: tap) }
                }
            }
            .containerRelativeFrame([.horizontal, .vertical])
            .environment(\.layoutDirection, .leftToRight)
        }
    }
}

struct PageCell: View {
    let path: String
    let crop: Bool
    let scale: ScaleType
    let start: ZoomStart
    let tap: (CGPoint) -> Void
    let held: ((CGImage) -> Void)?

    @State private var image: CGImage?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        ZStack {
            if let image {
                ZoomablePage(image: image, scale: scale, start: start, onTap: tap,
                             onLongPress: held.map { held in { held(image) } })
            } else {
                TapArea(tap: tap)
                if failed {
                    VStack(spacing: 12) {
                        Text("This page didn't load").foregroundStyle(.secondary)
                        Button("Try again") { attempt += 1 }.buttonStyle(.glass)
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .task(id: "\(attempt)-\(crop)") {
            guard let url = Server.shared.url(path) else { return }
            failed = false
            do {
                image = try await ImageStore.shared.image(url, maxPixel: nil, crop: crop ? .all : .none)
            } catch is CancellationError {
            } catch {
                failed = image == nil
            }
        }
    }
}

/// Catches taps where there's no page image to catch them.
struct TapArea: View {
    let tap: (CGPoint) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(.rect)
                .gesture(SpatialTapGesture().onEnded {
                    tap(CGPoint(x: $0.location.x / max(proxy.size.width, 1), y: $0.location.y / max(proxy.size.height, 1)))
                })
        }
    }
}

/// The card between chapters.
struct ChapterCard: View {
    let model: ReaderModel
    let item: ReaderItem

    var body: some View {
        let leaving = item == .after
        let other = leaving ? model.next : model.previous
        VStack(alignment: .leading, spacing: 18) {
            line(leaving ? "Finished" : "Current", model.chapter?.name ?? "")
            if let other {
                line(leaving ? "Next" : "Previous", other.name)
            } else {
                Text(leaving ? "There's no next chapter" : "There's no previous chapter")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(32)
        .allowsHitTesting(false)
    }

    private func line(_ label: String, _ name: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: label).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(verbatim: name).font(.title3.weight(.semibold))
        }
    }
}

// MARK: - Strip

struct StripGeometry: Equatable {
    var offset: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
}

struct StripReader: View {
    let model: ReaderModel
    @Binding var position: ScrollPosition
    @Binding var geometry: StripGeometry
    let crop: Bool
    let tap: (CGPoint) -> Void
    let held: ((CGImage) -> Void)?

    @AppStorage(Keys.stripPadding) private var padding = 0

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: model.mode == .strip ? 14 : 0) {
                ForEach(model.items, id: \.self) { item in
                    switch item {
                    case .page(let number):
                        StripPage(path: model.pages[number], crop: crop, aspect: model.aspects[number], held: held) {
                            model.aspects[number] = $0
                        }
                        .padding(.horizontal, geometry.width * CGFloat(padding) / 100)
                    case .before:
                        ChapterCard(model: model, item: item).frame(height: 260)
                    case .after:
                        VStack(spacing: 8) {
                            ChapterCard(model: model, item: item)
                            if let next = model.next {
                                Button("Next chapter") {
                                    Task { await model.open(next.id) }
                                }
                                .buttonStyle(.glassProminent)
                            }
                        }
                        .frame(height: 420)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .onScrollTargetVisibilityChange(idType: ReaderItem.self, threshold: 0.01) { visible in
            let pages = visible.compactMap { item -> Int? in
                if case .page(let number) = item { return number }
                return nil
            }
            if let last = pages.max() {
                model.arrived(.page(last))
            } else if let item = visible.first {
                model.arrived(item)
            }
        }
        .onScrollGeometryChange(for: StripGeometry.self) {
            StripGeometry(offset: $0.contentOffset.y, width: $0.containerSize.width, height: $0.containerSize.height)
        } action: { _, new in
            geometry = new
        }
        .onTapGesture { point in
            tap(CGPoint(x: point.x / max(geometry.width, 1), y: point.y / max(geometry.height, 1)))
        }
        .ignoresSafeArea()
    }
}

struct StripPage: View {
    let path: String
    let crop: Bool
    let aspect: CGFloat?
    let held: ((CGImage) -> Void)?
    let measured: (CGFloat) -> Void

    @State private var image: CGImage?
    @State private var failed = false
    @State private var attempt = 0

    private var trim: ImageStore.Crop { crop ? .sides : .none }

    var body: some View {
        let cached = image ?? Server.shared.url(path).flatMap { ImageStore.shared.cached($0, maxPixel: nil, crop: trim) }
        Color.clear
            .aspectRatio(cached.map { CGFloat($0.width) / CGFloat(max($0.height, 1)) } ?? aspect ?? 0.7, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if let cached {
                    Image(decorative: cached, scale: 1).resizable().scaledToFit()
                        .onLongPressGesture { held?(cached) }
                } else if failed {
                    Button("Try again") { attempt += 1 }.buttonStyle(.glass)
                } else {
                    ProgressView()
                }
            }
            .task(id: "\(attempt)-\(crop)") {
                guard let url = Server.shared.url(path) else { return }
                failed = false
                do {
                    let loaded = try await ImageStore.shared.image(url, maxPixel: nil, crop: trim)
                    measured(CGFloat(loaded.width) / CGFloat(max(loaded.height, 1)))
                    image = loaded
                } catch is CancellationError {
                } catch {
                    failed = cached == nil
                }
            }
    }
}
