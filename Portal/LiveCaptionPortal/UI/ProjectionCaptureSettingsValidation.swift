import SwiftUI

extension ProjectionCaptureSettingsInspector {
    func normalizeStoredValues() {
        projectionCaptureLanguageID = validatedLanguageID
        projectionCaptureVisibleLanguageIDs = ProjectionCaptureLanguageSelection.rawValue(
            from: selectedWindowLanguageIDs
        )
        projectionCapturePreviewArrangement = validatedPreviewArrangement.rawValue
        projectionCaptureVerticalPlacement = validatedVerticalPlacement.rawValue
        projectionCaptureWidth = clampedWidth(projectionCaptureWidth)
        projectionCaptureHeight = clampedHeight(projectionCaptureHeight)
        projectionCaptureFontID = validatedFontID
        projectionCaptureFontSize = clampedFontSize(projectionCaptureFontSize)
        projectionCaptureLineSpacing = clampedLineSpacing(projectionCaptureLineSpacing)
        projectionCapturePaddingHorizontal = clampedPadding(projectionCapturePaddingHorizontal)
        projectionCaptureAppendLineLimit = clampedAppendLineLimit(projectionCaptureAppendLineLimit)
    }

    func clampedWidth(_ value: Double) -> Double {
        min(max(value, WindowLayout.projectionCaptureMinimumWidth), maximumPreviewWidth)
    }

    func clampedHeight(_ value: Double) -> Double {
        min(
            max(value, WindowLayout.projectionCaptureMinimumHeight),
            WindowLayout.projectionCaptureMaximumHeight
        )
    }

    func clampedFontSize(_ value: Double) -> Double {
        min(
            max(value, WindowLayout.projectionCaptureMinimumFontSize),
            WindowLayout.projectionCaptureMaximumFontSize
        )
    }

    func clampedLineSpacing(_ value: Double) -> Double {
        min(
            max(value, WindowLayout.projectionCaptureMinimumLineSpacing),
            WindowLayout.projectionCaptureMaximumLineSpacing
        )
    }

    func clampedPadding(_ value: Double) -> Double {
        min(max(value, WindowLayout.projectionCaptureMinimumPadding), WindowLayout.projectionCaptureMaximumPadding)
    }

    func clampedAppendLineLimit(_ value: Double) -> Double {
        min(
            max(value, WindowLayout.projectionCaptureMinimumAppendLineLimit),
            WindowLayout.projectionCaptureMaximumAppendLineLimit
        )
    }
}
