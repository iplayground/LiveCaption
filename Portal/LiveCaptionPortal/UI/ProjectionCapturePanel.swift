import AppKit
import SwiftUI

enum ProjectionPreviewDisplayMode: String, CaseIterable, Identifiable {
    case inline
    case window

    var id: String { rawValue }

    static func mode(for rawValue: String) -> ProjectionPreviewDisplayMode {
        ProjectionPreviewDisplayMode(rawValue: rawValue) ?? .inline
    }
}

enum ProjectionCapturePreviewArrangement: String, CaseIterable, Identifiable {
    case vertical
    case horizontal

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .vertical:
            L10n.text("caption.projectionArrangement.vertical")
        case .horizontal:
            L10n.text("caption.projectionArrangement.horizontal")
        }
    }

    static func arrangement(for rawValue: String) -> ProjectionCapturePreviewArrangement {
        ProjectionCapturePreviewArrangement(rawValue: rawValue) ?? .vertical
    }
}

enum ProjectionCaptureLanguageSelection {
    static func selectedIDs(
        from rawValue: String,
        outputLanguages: [SpeechOutputLanguage],
        fallbackID: String
    ) -> [String] {
        let availableIDs = Set(outputLanguages.map(\.id))
        var selectedIDs: [String] = []

        rawValue
            .split(separator: ",")
            .map(String.init)
            .filter { availableIDs.contains($0) }
            .forEach { languageID in
                if !selectedIDs.contains(languageID), selectedIDs.count < 2 {
                    selectedIDs.append(languageID)
                }
            }

        if !selectedIDs.isEmpty {
            return selectedIDs
        }

        if availableIDs.contains(fallbackID) {
            return [fallbackID]
        }

        return outputLanguages.first.map { [$0.id] } ?? []
    }

    static func rawValue(from selectedIDs: [String]) -> String {
        selectedIDs.prefix(2).joined(separator: ",")
    }
}

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

@MainActor
final class ProjectionCaptureWindowPresenter: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var isClosingProgrammatically = false
    private let settingsInspectorHeight = 170.0
    private let frameStorageKey = "portal.projectionCaptureWindow"

    func update(
        inputLanguage: InputLanguage,
        outputLanguages: [SpeechOutputLanguage],
        captionPreviewState: SpeechCaptionPreviewState,
        isPresented: Bool,
        areConfigurationControlsLocked: Bool
    ) {
        guard isPresented else {
            close()
            return
        }

        let maximumContentWidth = Self.maximumContentWidth()
        let content = ProjectionCaptureWindowContent(
            inputLanguage: inputLanguage,
            outputLanguages: outputLanguages,
            captionPreviewState: captionPreviewState,
            maximumContentWidth: maximumContentWidth,
            settingsInspectorHeight: settingsInspectorHeight,
            areConfigurationControlsLocked: areConfigurationControlsLocked
        )

        if let window {
            window.contentView = NSHostingView(rootView: content)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialContentSize(maximumContentWidth: maximumContentWidth)),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("caption.projectionWindow.title")
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.contentView = NSHostingView(rootView: content)
        if !WindowFrameRestoration.restore(window: window, storageKey: frameStorageKey) {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func close() {
        guard let window else {
            return
        }

        isClosingProgrammatically = true
        window.close()
        isClosingProgrammatically = false
        self.window = nil
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            WindowFrameRestoration.save(window: window, storageKey: frameStorageKey)
        }

        window = nil

        if !isClosingProgrammatically {
            UserDefaults.standard.set(ProjectionPreviewDisplayMode.inline.rawValue, forKey: "projectionCapture.displayMode")
        }
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame(from: notification)
    }

    func windowDidResize(_ notification: Notification) {
        saveFrame(from: notification)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        saveFrame(from: notification)
    }

    private func initialContentSize(maximumContentWidth: Double) -> NSSize {
        let storedWidth = UserDefaults.standard.double(forKey: "projectionCapture.width")
        let storedHeight = UserDefaults.standard.double(forKey: "projectionCapture.height")
        let width = min(
            max(storedWidth == 0 ? 720 : storedWidth, WindowLayout.projectionCaptureMinimumWidth),
            maximumContentWidth
        )
        let height = min(
            max(storedHeight == 0 ? 180 : storedHeight, WindowLayout.projectionCaptureMinimumHeight),
            WindowLayout.projectionCaptureMaximumHeight
        )

        return NSSize(width: width, height: height + settingsInspectorHeight)
    }

    private static func maximumContentWidth() -> Double {
        let visibleWidths = NSScreen.screens.map {
            Double($0.visibleFrame.width - (WindowLayout.projectionCaptureHorizontalPadding * 2))
        }

        return max(WindowLayout.projectionCaptureMinimumWidth, visibleWidths.max() ?? WindowLayout.projectionCaptureMinimumWidth)
    }

    private func saveFrame(from notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        WindowFrameRestoration.save(window: window, storageKey: frameStorageKey)
    }
}

struct ProjectionCaptureWindowContent: View {
    let inputLanguage: InputLanguage
    let outputLanguages: [SpeechOutputLanguage]
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    let maximumContentWidth: Double
    let settingsInspectorHeight: Double
    let areConfigurationControlsLocked: Bool
    @AppStorage("projectionCapture.languageID") private var projectionCaptureLanguageID = "zh-Hant"
    @AppStorage("projectionCapture.visibleLanguageIDs") private var projectionCaptureVisibleLanguageIDs = ""
    @AppStorage("projectionCapture.previewArrangement") private var projectionCapturePreviewArrangement = ProjectionCapturePreviewArrangement.vertical.rawValue
    @AppStorage("projectionCapture.width") private var projectionCaptureWidth = 720.0
    @AppStorage("projectionCapture.height") private var projectionCaptureHeight = 180.0
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
        .background(ProjectionCaptureWindowMinimumSizeSynchronizer(minimumContentSize: minimumContentSize))
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
                captionPreviewState: captionPreviewState
            )
            .frame(width: previewSize.width, height: previewSize.height)
        }
        .frame(width: previewSize.width, alignment: .leading)
    }

    private func languageName(for languageID: String) -> String {
        outputLanguages.first { $0.id == languageID }?.nativeName ?? languageID
    }
}

private struct ProjectionCaptureWindowMinimumSizeSynchronizer: NSViewRepresentable {
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
            if needsResize || !NSEqualRects(window.frame, adjustedFrame) {
                window.setFrame(adjustedFrame, display: true)
            }
        }
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
    @AppStorage("projectionCapture.verticalPlacement") private var projectionCaptureVerticalPlacement = ProjectionCaptionVerticalPlacement.bottom.rawValue

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
