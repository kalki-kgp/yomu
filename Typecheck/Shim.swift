// Not part of the app. Stands in for App/Kit/Platform.swift and App/Reader/Zoomable.swift so
// `Typecheck/check.sh` can typecheck everything else against the macOS SDK.

import SwiftUI

extension View {
    func inlineTitle() -> some View { self }

    func hidesStatusBar(_ hidden: Bool) -> some View { self }
    func minimizingTabBar() -> some View { self }
    func addressField() -> some View { self }
    func plainField() -> some View { self }
}

final class AppDelegate: NSObject {}

@propertyWrapper struct UIApplicationDelegateAdaptor<Delegate: NSObject> {
    var wrappedValue: Delegate
    init(_ type: Delegate.Type) { wrappedValue = Delegate() }
}

enum Platform {
    static func keepAwake(_ on: Bool) {}
    static func setBrightness(_ value: CGFloat?) {}
    static func lock(_ rotation: ReaderRotation) {}
    static func share(_ image: CGImage) {}
}

struct ZoomablePage: View {
    let image: CGImage
    var scale: ScaleType = .fitScreen
    var start: ZoomStart = .center
    let onTap: (CGPoint) -> Void
    var onLongPress: (() -> Void)? = nil

    var body: some View { Color.clear }
}
