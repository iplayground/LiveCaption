import AppKit
import SwiftUI

struct ProjectionCaptureWindowContent: View {
    let inputLanguage: InputLanguage
    let outputLanguages: [SpeechOutputLanguage]
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    let maximumContentWidth: Double
    let settingsInspectorHeight: Double
    let areConfigurationControlsLocked: Bool
    @AppStorage("projectionCapture.languageID") private var projectionCaptureLanguageID = "zh-Hant"
    @AppStorage("projectionCapture.visibleLanguageIDs") private var projectionCaptureVisibleLanguageIDs = ""
    @AppStorage("projectionCapture.previewArrangement")
    private var projectionCapturePreviewArrangement = ProjectionCapturePreviewArrangement.vertical.rawValue
    @AppStorage("projectionCapture.width") private var projectionCaptureWidth = 720.0
    @AppStorage("projectionCapture.height") private var projectionCaptureHeight = 180.0
    @AppStorage("projectionCapture.captionSource")
    private var projectionCaptureCaptionSource = ProjectionCaptionSource.speech.rawValue
    @State private var screenMaximumContentWidth: Double?

    private let languageHeaderHeight = 24.0
    private let languageHeaderPreviewSpacing = 6.0
    private let previewBlockSpacing = WindowLayout.projectionCapturePreviewBlockSpacing
    private let previewStageTopPadding = 10.0
    private let previewStageBottomPadding = 20.0
    private let dividerHeight = 1.0

    private var effectiveMaximumContentWidth: Double {
        max(1, screenMaximumContentWidth ?? maximumContentWidth)
    }

    private var selectedLanguageIDs: [String] {
        ProjectionCaptureLanguageSelection.selectedIDs(
            from: projectionCaptureVisibleLanguageIDs,
            outputLanguages: outputLanguages,
            fallbackID: validatedLanguageID
        )
    }

    private var validatedLanguageID: String {
        if outputLanguages.contains(where: { $0.id == projectionCaptureLanguageID }) {
            return projectionCaptureLanguageID
        }

        if outputLanguages.contains(where: { $0.id == inputLanguage.matchingOutputLanguageID }) {
            return inputLanguage.matchingOutputLanguageID
        }

        return outputLanguages.first?.id ?? projectionCaptureLanguageID
    }

    private var previewSize: CGSize {
        CGSize(
            width: previewWidth,
            height: min(
                max(projectionCaptureHeight, WindowLayout.projectionCaptureMinimumHeight),
                WindowLayout.projectionCaptureMaximumHeight
            )
        )
    }

    private var previewWidth: Double {
        let requestedWidth = max(projectionCaptureWidth, WindowLayout.projectionCaptureMinimumWidth)

        switch previewArrangement {
        case .vertical:
            return min(requestedWidth, effectiveMaximumContentWidth)
        case .horizontal:
            let availableBlockWidth = (effectiveMaximumContentWidth - previewBlockSpacing) / 2
            return min(requestedWidth, max(1, availableBlockWidth))
        }
    }

    private var previewArrangement: ProjectionCapturePreviewArrangement {
        guard selectedLanguageIDs.count == 2 else {
            return .vertical
        }

        return ProjectionCapturePreviewArrangement.arrangement(for: projectionCapturePreviewArrangement)
    }

    private var captionSource: CaptionQualityMode {
        ProjectionCaptionSource.source(for: projectionCaptureCaptionSource).captionMode
    }

    private var previewStackWidth: Double {
        let count = max(selectedLanguageIDs.count, 1)

        switch previewArrangement {
        case .vertical:
            return previewSize.width
        case .horizontal:
            let blocks = Double(count) * previewSize.width
            let spacing = Double(max(count - 1, 0)) * previewBlockSpacing
            return blocks + spacing
        }
    }

    private var previewStackHeight: Double {
        let count = max(selectedLanguageIDs.count, 1)

        switch previewArrangement {
        case .vertical:
            let blocks = Double(count) * previewBlockHeight
            let spacing = Double(max(count - 1, 0)) * previewBlockSpacing
            return blocks + spacing
        case .horizontal:
            return previewBlockHeight
        }
    }

    private var previewBlockHeight: Double {
        languageHeaderHeight + languageHeaderPreviewSpacing + previewSize.height
    }

    private var previewStageHeight: Double {
        previewStageTopPadding + previewStackHeight + previewStageBottomPadding
    }

    private var minimumContentSize: CGSize {
        CGSize(
            width: previewStackWidth + (WindowLayout.projectionCaptureHorizontalPadding * 2),
            height: settingsInspectorHeight + dividerHeight + previewStageHeight
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let containerWidth = max(geometry.size.width, minimumContentSize.width)
            let contentHeight = max(geometry.size.height, minimumContentSize.height)

            VStack(spacing: 0) {
                ProjectionCaptureSettingsInspector(
                    inputLanguage: inputLanguage,
                    outputLanguages: outputLanguages,
                    captionPreviewState: captionPreviewState,
                    maximumWidth: effectiveMaximumContentWidth,
                    preferredWidth: nil,
                    areConfigurationControlsLocked: areConfigurationControlsLocked
                )
                .frame(width: containerWidth, height: settingsInspectorHeight, alignment: .top)

                Divider()
                    .frame(height: dividerHeight)

                ProjectionCaptureLanguageStackView(
                    inputLanguage: inputLanguage,
                    languageIDs: selectedLanguageIDs,
                    outputLanguages: outputLanguages,
                    captionPreviewState: captionPreviewState,
                    captionSource: captionSource,
                    previewSize: previewSize,
                    arrangement: previewArrangement,
                    languageHeaderHeight: languageHeaderHeight,
                    languageHeaderPreviewSpacing: languageHeaderPreviewSpacing,
                    previewBlockSpacing: previewBlockSpacing,
                    topPadding: previewStageTopPadding,
                    bottomPadding: previewStageBottomPadding
                )
                .frame(width: containerWidth, height: previewStageHeight, alignment: .top)
                .frame(width: containerWidth, alignment: .top)
            }
            .frame(width: containerWidth, height: contentHeight, alignment: .top)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: minimumContentSize.width, minHeight: minimumContentSize.height)
        .background(ProjectionCaptureWindowScreenWidthReader(maximumContentWidth: $screenMaximumContentWidth))
        .background(ProjectionWindowSizeSync(minimumContentSize: minimumContentSize))
    }
}

private struct ProjectionCaptureWindowScreenWidthReader: NSViewRepresentable {
    @Binding var maximumContentWidth: Double?

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else {
                return
            }

            let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            guard let visibleFrame else {
                return
            }

            let width = max(1, Double(visibleFrame.width - (WindowLayout.projectionCaptureHorizontalPadding * 2)))
            if maximumContentWidth != width {
                maximumContentWidth = width
            }
        }
    }
}

private struct ProjectionCaptureLanguageStackView: View {
    let inputLanguage: InputLanguage
    let languageIDs: [String]
    let outputLanguages: [SpeechOutputLanguage]
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    let captionSource: CaptionQualityMode
    let previewSize: CGSize
    let arrangement: ProjectionCapturePreviewArrangement
    let languageHeaderHeight: Double
    let languageHeaderPreviewSpacing: Double
    let previewBlockSpacing: Double
    let topPadding: Double
    let bottomPadding: Double

    var body: some View {
        previewBlocks
            .padding(.horizontal, WindowLayout.projectionCaptureHorizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var previewBlocks: some View {
        switch arrangement {
        case .vertical:
            VStack(alignment: .center, spacing: previewBlockSpacing) {
                previewBlockList
            }
        case .horizontal:
            HStack(alignment: .top, spacing: previewBlockSpacing) {
                previewBlockList
            }
        }
    }

    private var previewBlockList: some View {
        ForEach(languageIDs, id: \.self) { languageID in
            previewBlock(for: languageID)
        }
    }

    private func previewBlock(for languageID: String) -> some View {
        VStack(alignment: .leading, spacing: languageHeaderPreviewSpacing) {
            Text(languageName(for: languageID))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: previewSize.width, height: languageHeaderHeight, alignment: .bottomLeading)

            ProjectionCaptureView(
                inputLanguage: inputLanguage,
                languageID: languageID,
                outputLanguages: outputLanguages,
                captionPreviewState: captionPreviewState,
                captionSource: captionSource
            )
            .frame(width: previewSize.width, height: previewSize.height)
        }
        .frame(width: previewSize.width, alignment: .leading)
    }

    private func languageName(for languageID: String) -> String {
        outputLanguages.first { $0.id == languageID }?.nativeName ?? languageID
    }
}

private struct ProjectionWindowSizeSync: NSViewRepresentable {
    let minimumContentSize: CGSize

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else {
                return
            }

            let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size
            let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            let visibleFrameSize = visibleFrame.map {
                NSSize(
                    width: min(frameSize.width, $0.width),
                    height: min(frameSize.height, $0.height)
                )
            } ?? frameSize
            window.minSize = visibleFrameSize

            var frame = window.frame
            var needsResize = false

            if window.contentLayoutRect.width < minimumContentSize.width {
                frame.size.width = visibleFrameSize.width
                needsResize = true
            }

            if window.contentLayoutRect.height < minimumContentSize.height {
                frame.origin.y -= visibleFrameSize.height - frame.height
                frame.size.height = visibleFrameSize.height
                needsResize = true
            }

            let adjustedFrame = WindowFrameRestoration.adjustedFrame(frame, visibleFrame: visibleFrame)
            if needsResize || window.frame != adjustedFrame {
                window.setFrame(adjustedFrame, display: true)
            }
        }
    }
}
