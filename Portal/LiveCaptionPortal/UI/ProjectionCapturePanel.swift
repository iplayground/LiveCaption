import AppKit
import SwiftUI

struct ProjectionCaptureSection: View {
    let inputLanguage: InputLanguage
    let outputLanguages: [SpeechOutputLanguage]
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    @AppStorage("projectionCapture.languageID") private var projectionCaptureLanguageID = "zh-Hant"
    @AppStorage("projectionCapture.width") private var projectionCaptureWidth = 720.0
    @AppStorage("projectionCapture.height") private var projectionCaptureHeight = 180.0

    private var selectedProjectionLanguageID: String {
        if outputLanguages.contains(where: { $0.id == projectionCaptureLanguageID }) {
            return projectionCaptureLanguageID
        }

        return outputLanguages.first?.id ?? inputLanguage.matchingOutputLanguageID
    }

    var body: some View {
        GeometryReader { geometry in
            let maximumWidth = WindowLayout.projectionCaptureMaximumWidth(for: geometry.size.width)
            let visibleWidth = clampedWidth(projectionCaptureWidth, maximumWidth: maximumWidth)
            let visibleHeight = clampedHeight(projectionCaptureHeight)

            VStack(alignment: .leading, spacing: 0) {
                ProjectionCaptureView(
                    inputLanguage: inputLanguage,
                    languageID: selectedProjectionLanguageID,
                    outputLanguages: outputLanguages,
                    captionPreviewState: captionPreviewState
                )
                .frame(width: visibleWidth, height: visibleHeight)
            }
            .padding(.horizontal, WindowLayout.projectionCaptureHorizontalPadding)
            .padding(.vertical, WindowLayout.projectionCaptureVerticalPadding)
            .frame(width: geometry.size.width, alignment: .leading)
        }
        .frame(height: clampedHeight(projectionCaptureHeight) + (WindowLayout.projectionCaptureVerticalPadding * 2))
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func clampedWidth(_ value: Double, maximumWidth: Double) -> Double {
        min(max(value, WindowLayout.projectionCaptureMinimumWidth), maximumWidth)
    }

    private func clampedHeight(_ value: Double) -> Double {
        min(max(value, WindowLayout.projectionCaptureMinimumHeight), WindowLayout.projectionCaptureMaximumHeight)
    }
}

struct ProjectionCaptureView: View {
    let inputLanguage: InputLanguage
    let languageID: String
    let outputLanguages: [SpeechOutputLanguage]
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    @AppStorage("projectionCapture.fontID") private var projectionCaptureFontID = ProjectionCaptionFontChoice.systemID
    @AppStorage("projectionCapture.fontSize") private var projectionCaptureFontSize = 32.0
    @AppStorage("projectionCapture.lineSpacing") private var projectionCaptureLineSpacing = 6.0
    @AppStorage("projectionCapture.appendsText") private var projectionCaptureAppendsText = false
    @AppStorage("projectionCapture.appendLineLimit") private var projectionCaptureAppendLineLimit = 3.0
    @AppStorage("projectionCapture.paddingHorizontal") private var projectionCapturePaddingHorizontal = 28.0

    private var selectedLanguage: SpeechOutputLanguage? {
        outputLanguages.first { $0.id == languageID }
    }

    private var captionText: String {
        captionPreviewState.projectionCaptionText(
            for: selectedLanguage,
            inputLanguage: inputLanguage,
            appendsText: projectionCaptureAppendsText,
            appendLineLimit: Int(clampedAppendLineLimit(projectionCaptureAppendLineLimit).rounded())
        )
    }

    private var captionFont: Font {
        let fontChoice = ProjectionCaptionFontChoice.choice(for: projectionCaptureFontID)

        if let familyName = fontChoice.familyName {
            return .custom(familyName, size: captionFontSize).weight(.semibold)
        }

        return .system(size: captionFontSize, weight: .semibold)
    }

    private var captionFontSize: Double {
        min(
            max(projectionCaptureFontSize, WindowLayout.projectionCaptureMinimumFontSize),
            WindowLayout.projectionCaptureMaximumFontSize
        )
    }

    private var captionLineSpacing: Double {
        min(
            max(projectionCaptureLineSpacing, WindowLayout.projectionCaptureMinimumLineSpacing),
            WindowLayout.projectionCaptureMaximumLineSpacing
        )
    }

    private var captionNSFont: NSFont {
        let fontChoice = ProjectionCaptionFontChoice.choice(for: projectionCaptureFontID)

        if let familyName = fontChoice.familyName,
           let font = NSFontManager.shared.font(
            withFamily: familyName,
            traits: [],
            weight: 9,
            size: captionFontSize
           ) {
            return font
        }

        return .systemFont(ofSize: captionFontSize, weight: .semibold)
    }

    private var contentPadding: EdgeInsets {
        let vertical = 20.0
        let horizontal = clampedPadding(projectionCapturePaddingHorizontal)
        return EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }

    var body: some View {
        ZStack {
            Color.white

            GeometryReader { geometry in
                let lineSpacing = captionLineSpacing
                let padding = contentPadding
                let availableSize = CGSize(
                    width: max(0, geometry.size.width - padding.leading - padding.trailing),
                    height: max(0, geometry.size.height - padding.top - padding.bottom)
                )
                let visibleText = ProjectionCaptionTextTruncator.visibleSuffix(
                    of: captionText,
                    fitting: availableSize,
                    font: captionNSFont,
                    lineSpacing: lineSpacing
                )

                ProjectionCaptionTextView(
                    text: visibleText,
                    font: captionNSFont,
                    lineSpacing: lineSpacing
                )
                    .frame(width: availableSize.width, height: availableSize.height, alignment: .bottomLeading)
                    .padding(padding)
                    .clipped()
            }
        }
        .clipShape(Rectangle())
        .overlay {
            Rectangle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .accessibilityLabel(L10n.text("caption.projectionCapture"))
    }

    private func clampedPadding(_ value: Double) -> Double {
        min(max(value, WindowLayout.projectionCaptureMinimumPadding), WindowLayout.projectionCaptureMaximumPadding)
    }

    private func clampedAppendLineLimit(_ value: Double) -> Double {
        min(
            max(value, WindowLayout.projectionCaptureMinimumAppendLineLimit),
            WindowLayout.projectionCaptureMaximumAppendLineLimit
        )
    }
}
