// The reader's settings, in Mihon's three pages: reading mode, general, and custom filter.
// The same pages are reachable from More, Settings, where there's no series to apply to.

import SwiftUI

struct ReaderSettings: View {
    let model: ReaderModel?

    @State private var page = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if model == nil {
            pages
        } else {
            NavigationStack { pages }
                // Half height and no dimming, so a filter can be judged against the page behind it.
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    private var pages: some View {
        Form {
            Picker("Page", selection: $page) {
                Text("Reading mode").tag(0)
                Text("General").tag(1)
                Text("Custom filter").tag(2)
            }
            .pickerStyle(.segmented)
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
            switch page {
            case 0: ReadingModePage(model: model)
            case 1: GeneralPage()
            default: FilterPage()
            }
        }
        .navigationTitle("Reader")
        .inlineTitle()
        .toolbar {
            if model != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}

private struct ReadingModePage: View {
    let model: ReaderModel?

    @AppStorage(Keys.readingMode) private var standardMode = ReadingMode.rtl
    @AppStorage(Keys.rotation) private var standardRotation = ReaderRotation.free
    @AppStorage(Keys.pagerTaps) private var pagerTaps = TapLayout.standard
    @AppStorage(Keys.pagerInvert) private var pagerInvert = TapInvert.none
    @AppStorage(Keys.stripTaps) private var stripTaps = TapLayout.standard
    @AppStorage(Keys.stripInvert) private var stripInvert = TapInvert.none
    @AppStorage(Keys.scaleType) private var scale = ScaleType.fitScreen
    @AppStorage(Keys.zoomStart) private var zoomStart = ZoomStart.automatic
    @AppStorage(Keys.cropPaged) private var cropPaged = false
    @AppStorage(Keys.cropStrip) private var cropStrip = false
    @AppStorage(Keys.stripPadding) private var padding = 0

    var body: some View {
        if let model {
            Section("For this series") {
                Picker("Reading mode", selection: .init(get: { model.mode }, set: { model.use($0) })) {
                    ForEach(ReadingMode.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                Picker("Rotation", selection: .init(get: { model.rotation }, set: { model.use($0) })) {
                    ForEach(ReaderRotation.allCases) { Text(verbatim: $0.title).tag($0) }
                }
            }
        } else {
            Section("Default") {
                Picker("Reading mode", selection: $standardMode) {
                    ForEach(ReadingMode.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                Picker("Rotation", selection: $standardRotation) {
                    ForEach(ReaderRotation.allCases) { Text(verbatim: $0.title).tag($0) }
                }
            }
        }
        // In the reader only the mode in use is shown, as in Mihon; in Settings, both.
        if model?.mode.isPaged ?? true {
            Section("Paged") {
                Picker("Tap zones", selection: $pagerTaps) {
                    ForEach(TapLayout.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                if pagerTaps != .disabled {
                    Picker("Invert tap zones", selection: $pagerInvert) {
                        ForEach(TapInvert.allCases) { Text(verbatim: $0.title).tag($0) }
                    }
                }
                Picker("Scale type", selection: $scale) {
                    ForEach(ScaleType.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                Picker("Zoom start position", selection: $zoomStart) {
                    ForEach(ZoomStart.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                Toggle("Crop borders", isOn: $cropPaged)
            }
        }
        if !(model?.mode.isPaged ?? false) {
            Section("Long strip") {
                Picker("Tap zones", selection: $stripTaps) {
                    ForEach(TapLayout.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                if stripTaps != .disabled {
                    Picker("Invert tap zones", selection: $stripInvert) {
                        ForEach(TapInvert.allCases) { Text(verbatim: $0.title).tag($0) }
                    }
                }
                Stepped(title: "Side padding", value: $padding, range: 0...25, unit: "%")
                Toggle("Crop borders", isOn: $cropStrip)
            }
        }
    }
}

private struct GeneralPage: View {
    @AppStorage(Keys.readerTheme) private var theme = ReaderTheme.black
    @AppStorage(Keys.showPageNumber) private var showPageNumber = true
    @AppStorage(Keys.fullscreen) private var fullscreen = true
    @AppStorage(Keys.keepAwake) private var keepAwake = true
    @AppStorage(Keys.longTap) private var longTap = true
    @AppStorage(Keys.alwaysTransition) private var alwaysTransition = true
    @AppStorage(Keys.pageTransitions) private var pageTransitions = true

    var body: some View {
        Section {
            Picker("Background color", selection: $theme) {
                ForEach(ReaderTheme.allCases) { Text(verbatim: $0.title).tag($0) }
            }
        }
        Section {
            Toggle("Show page number", isOn: $showPageNumber)
            Toggle("Fullscreen", isOn: $fullscreen)
            Toggle("Keep screen on", isOn: $keepAwake)
            Toggle("Show actions on long tap", isOn: $longTap)
            Toggle("Always show chapter transition", isOn: $alwaysTransition)
            Toggle("Animate page transitions", isOn: $pageTransitions)
        }
    }
}

private struct FilterPage: View {
    @AppStorage(Keys.customBrightness) private var customBrightness = false
    @AppStorage(Keys.brightnessValue) private var brightnessValue = 0
    @AppStorage(Keys.colorFilter) private var colorFilter = false
    @AppStorage(Keys.filterRed) private var red = 0
    @AppStorage(Keys.filterGreen) private var green = 0
    @AppStorage(Keys.filterBlue) private var blue = 0
    @AppStorage(Keys.filterAlpha) private var alpha = 0
    @AppStorage(Keys.filterBlend) private var blend = FilterBlend.standard
    @AppStorage(Keys.grayscale) private var grayscale = false
    @AppStorage(Keys.inverted) private var inverted = false

    var body: some View {
        Section {
            Toggle("Custom brightness", isOn: $customBrightness)
            if customBrightness {
                Stepped(title: "Brightness", value: $brightnessValue, range: -75...100, unit: "")
            }
        }
        Section {
            Toggle("Custom color filter", isOn: $colorFilter)
            if colorFilter {
                Stepped(title: "R", value: $red, range: 0...255, unit: "")
                Stepped(title: "G", value: $green, range: 0...255, unit: "")
                Stepped(title: "B", value: $blue, range: 0...255, unit: "")
                Stepped(title: "A", value: $alpha, range: 0...255, unit: "")
                Picker("Color filter blend mode", selection: $blend) {
                    ForEach(FilterBlend.allCases) { Text(verbatim: $0.title).tag($0) }
                }
            }
        }
        Section {
            Toggle("Grayscale", isOn: $grayscale)
            Toggle("Inverted", isOn: $inverted)
        }
    }
}

/// A whole-number slider with its value beside it.
private struct Stepped: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: title).frame(minWidth: 28, alignment: .leading)
            Slider(value: .init(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
            Text(verbatim: "\(value)\(unit)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
        }
    }
}
