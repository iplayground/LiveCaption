import SwiftUI
import AppKit

enum WindowLayout {
    static let controlSidebarWidth: CGFloat = 280
    static let statusSidebarWidth: CGFloat = 300
    static let audioSourcePickerWidth: CGFloat = 208
    static let logDrawerHeaderHeight: CGFloat = 50
    static let defaultLogDrawerContentHeight: CGFloat = 220
    static let headerEstimatedHeight: CGFloat = 86
    static let projectionCaptureHorizontalPadding: CGFloat = 20
    static let projectionCaptureVerticalPadding: CGFloat = 14
    static let projectionCapturePreviewBlockSpacing = 12.0
    static let projectionCaptureMinimumWidth = 600.0
    static let projectionCaptureMinimumHeight = 100.0
    static let projectionCaptureMaximumHeight = 300.0
    static let projectionCaptureMinimumFontSize = 24.0
    static let projectionCaptureMaximumFontSize = 72.0
    static let projectionCaptureMinimumLineSpacing = 0.0
    static let projectionCaptureMaximumLineSpacing = 24.0
    static let projectionCaptureMinimumPadding = 0.0
    static let projectionCaptureMaximumPadding = 80.0
    static let projectionCaptureMinimumAppendLineLimit = 1.0
    static let projectionCaptureMaximumAppendLineLimit = 10.0
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

    static func projectionCaptureMaximumWidth(for containerWidth: CGFloat) -> Double {
        max(
            projectionCaptureMinimumWidth,
            Double(containerWidth - (projectionCaptureHorizontalPadding * 2))
        )
    }
}

enum ControlPalette {
    static let secondaryButtonBackground = Color.primary.opacity(0.08)
}
