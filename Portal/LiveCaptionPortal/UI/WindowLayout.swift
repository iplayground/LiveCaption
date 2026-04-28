import SwiftUI
import AppKit

enum WindowLayout {
    static let controlSidebarWidth: CGFloat = 280
    static let statusSidebarWidth: CGFloat = 300
    static let audioSourcePickerWidth: CGFloat = 208
    static let logDrawerHeaderHeight: CGFloat = 50
    private static let preferredMinimumSize = CGSize(width: 1280, height: 820)

    static var minimumSize: CGSize {
        guard let visibleSize = NSScreen.main?.visibleFrame.size else {
            return preferredMinimumSize
        }

        return CGSize(
            width: min(preferredMinimumSize.width, visibleSize.width),
            height: min(preferredMinimumSize.height, visibleSize.height)
        )
    }
}

enum ControlPalette {
    static let secondaryButtonBackground = Color.primary.opacity(0.08)
}
