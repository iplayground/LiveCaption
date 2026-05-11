import AppKit
import SwiftUI

enum WindowFrameRestoration {
    static func restore(window: NSWindow, storageKey: String) -> Bool {
        guard var frame = storedFrame(storageKey: storageKey) else {
            return false
        }

        let screen = storedScreen(storageKey: storageKey) ?? bestScreen(for: frame) ?? NSScreen.main
        frame = adjustedFrame(frame, visibleFrame: screen?.visibleFrame)
        window.setFrame(frame, display: true)
        return true
    }

    static func save(window: NSWindow, storageKey: String) {
        let defaults = UserDefaults.standard
        let frame = window.frame
        defaults.set(frame.origin.x, forKey: "\(storageKey).frame.x")
        defaults.set(frame.origin.y, forKey: "\(storageKey).frame.y")
        defaults.set(frame.size.width, forKey: "\(storageKey).frame.width")
        defaults.set(frame.size.height, forKey: "\(storageKey).frame.height")

        if let screenID = window.screen?.displayID {
            defaults.set(Int(screenID), forKey: "\(storageKey).screenID")
        }
    }

    static func adjustedFrame(_ frame: NSRect, visibleFrame: NSRect?) -> NSRect {
        guard let visibleFrame else {
            return frame
        }

        var adjustedFrame = frame
        adjustedFrame.size.width = min(adjustedFrame.width, visibleFrame.width)
        adjustedFrame.size.height = min(adjustedFrame.height, visibleFrame.height)

        if adjustedFrame.maxX > visibleFrame.maxX {
            adjustedFrame.origin.x = visibleFrame.maxX - adjustedFrame.width
        }

        if adjustedFrame.minX < visibleFrame.minX {
            adjustedFrame.origin.x = visibleFrame.minX
        }

        if adjustedFrame.maxY > visibleFrame.maxY {
            adjustedFrame.origin.y = visibleFrame.maxY - adjustedFrame.height
        }

        if adjustedFrame.minY < visibleFrame.minY {
            adjustedFrame.origin.y = visibleFrame.minY
        }

        return adjustedFrame
    }

    private static func storedFrame(storageKey: String) -> NSRect? {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: "\(storageKey).frame.width")
        let height = defaults.double(forKey: "\(storageKey).frame.height")

        guard width > 0, height > 0 else {
            return nil
        }

        return NSRect(
            x: defaults.double(forKey: "\(storageKey).frame.x"),
            y: defaults.double(forKey: "\(storageKey).frame.y"),
            width: width,
            height: height
        )
    }

    private static func storedScreen(storageKey: String) -> NSScreen? {
        let screenID = UserDefaults.standard.integer(forKey: "\(storageKey).screenID")
        guard screenID != 0 else {
            return nil
        }

        return NSScreen.screens.first { $0.displayID == CGDirectDisplayID(screenID) }
    }

    private static func bestScreen(for frame: NSRect) -> NSScreen? {
        let frameCenter = NSPoint(x: frame.midX, y: frame.midY)
        if let containingScreen = NSScreen.screens.first(where: { NSPointInRect(frameCenter, $0.visibleFrame) }) {
            return containingScreen
        }

        return NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        }
    }
}

struct WindowFrameRestorationBridge: NSViewRepresentable {
    let storageKey: String
    let minimumSize: CGSize

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else {
                return
            }

            context.coordinator.attach(to: window, storageKey: storageKey, minimumSize: minimumSize)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var storageKey = ""
        private var observers: [NSObjectProtocol] = []

        deinit {
            removeObservers()
        }

        func attach(to window: NSWindow, storageKey: String, minimumSize: CGSize) {
            guard self.window !== window || self.storageKey != storageKey else {
                return
            }

            removeObservers()
            self.window = window
            self.storageKey = storageKey
            window.minSize = minimumSize
            _ = WindowFrameRestoration.restore(window: window, storageKey: storageKey)
            installObservers(for: window)
        }

        private func installObservers(for window: NSWindow) {
            let center = NotificationCenter.default
            let notifications: [Notification.Name] = [
                NSWindow.didMoveNotification,
                NSWindow.didResizeNotification,
                NSWindow.didChangeScreenNotification,
                NSWindow.willCloseNotification
            ]

            observers = notifications.map { notification in
                center.addObserver(forName: notification, object: window, queue: .main) { [weak self] _ in
                    self?.save()
                }
            }
        }

        private func save() {
            guard let window else {
                return
            }

            WindowFrameRestoration.save(window: window, storageKey: storageKey)
        }

        private func removeObservers() {
            let center = NotificationCenter.default
            observers.forEach(center.removeObserver)
            observers.removeAll()
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

private extension NSRect {
    var area: CGFloat {
        width * height
    }
}
