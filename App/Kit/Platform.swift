// The handful of iPhone-only calls, behind names the rest of the app uses. Keeping them in one
// file lets everything else be typechecked on a Mac that only has the Command Line Tools.

import SwiftUI
import UIKit

extension View {
    func inlineTitle() -> some View {
        navigationBarTitleDisplayMode(.inline)
    }

    func hidesStatusBar(_ hidden: Bool) -> some View {
        statusBarHidden(hidden)
    }

    func minimizingTabBar() -> some View {
        tabBarMinimizeBehavior(.onScrollDown)
    }

    func addressField() -> some View {
        keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
    }

    func plainField() -> some View {
        textInputAutocapitalization(.never).autocorrectionDisabled()
    }
}

/// Only here so the reader can say which ways the screen may turn.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientations: UIInterfaceOrientationMask = .allButUpsideDown

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientations
    }
}

enum Platform {
    private static var systemBrightness: CGFloat?

    private static var scenes: [UIWindowScene] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    }

    static func keepAwake(_ on: Bool) {
        UIApplication.shared.isIdleTimerDisabled = on
    }

    /// Sets the screen's brightness, 0 to 1, remembering what it was. Nil puts that back.
    static func setBrightness(_ value: CGFloat?) {
        guard let screen = scenes.first?.screen else { return }
        if let value {
            if systemBrightness == nil { systemBrightness = screen.brightness }
            screen.brightness = value
        } else if let saved = systemBrightness {
            screen.brightness = saved
            systemBrightness = nil
        }
    }

    static func lock(_ rotation: ReaderRotation) {
        let mask: UIInterfaceOrientationMask
        switch rotation {
        case .free: mask = .allButUpsideDown
        case .portrait: mask = .portrait
        case .landscape: mask = .landscape
        }
        guard AppDelegate.orientations != mask else { return }
        AppDelegate.orientations = mask
        for scene in scenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
            var controller = scene.keyWindow?.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
        }
    }

    /// The system share sheet for a page: save to Photos, copy, send.
    static func share(_ image: CGImage) {
        guard var top = scenes.first?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        top.present(UIActivityViewController(activityItems: [UIImage(cgImage: image)], applicationActivities: nil), animated: true)
    }
}
