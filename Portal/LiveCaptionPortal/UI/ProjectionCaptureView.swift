import SwiftUI

struct ProjectionCaptureView: View {
    let inputLanguage: InputLanguage
    let languageID: String
    let outputLanguages: [SpeechOutputLanguage]
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    var captionSource: CaptionQualityMode = .fast
    @AppStorage("projectionCapture.fontID") private var projectionCaptureFontID = ProjectionCaptionFontChoice.systemID
    @AppStorage("projectionCapture.fontSize") private var projectionCaptureFontSize = 32.0
    @AppStorage("projectionCapture.lineSpacing") private var projectionCaptureLineSpacing = 6.0
    @AppStorage("projectionCapture.appendsText") private var projectionCaptureAppendsText = false
    @AppStorage("projectionCapture.appendLineLimit") private var projectionCaptureAppendLineLimit = 3.0
    @AppStorage("projectionCapture.paddingHorizontal") private var projectionCapturePaddingHorizontal = 28.0
    @AppStorage("projectionCapture.verticalPlacement")
    private var projectionCaptureVerticalPlacement = ProjectionCaptionVerticalPlacement.bottom.rawValue

    private var selectedLanguage: SpeechOutputLanguage? {
        outputLanguages.first { $0.id == languageID }
    }

    private var captionText: String {
        captionPreviewState.projectionCaptionText(
            for: selectedLanguage,
            inputLanguage: inputLanguage,
            source: captionSource,
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

    private var verticalPlacement: ProjectionCaptionVerticalPlacement {
        ProjectionCaptionVerticalPlacement.placement(for: projectionCaptureVerticalPlacement)
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
                let visibleText = ProjectionCaptionTextTruncator.visibleText(
                    of: captionText,
                    fitting: availableSize,
                    font: captionNSFont,
                    lineSpacing: lineSpacing,
                    verticalPlacement: verticalPlacement
                )

                ProjectionCaptionTextView(
                    text: visibleText,
                    font: captionNSFont,
                    lineSpacing: lineSpacing,
                    verticalPlacement: verticalPlacement
                )
                    .frame(width: availableSize.width, height: availableSize.height, alignment: frameAlignment)
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

    private var frameAlignment: Alignment {
        switch verticalPlacement {
        case .top:
            return .topLeading
        case .bottom:
            return .bottomLeading
        }
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
