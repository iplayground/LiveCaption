import AppKit
import SwiftUI

struct ControlSidebar: View {
    @ObservedObject var audioInputController: AudioInputController
    @Binding var subtitleFileSettings: SubtitleFileSettings
    @Binding var subtitleFileAccessStatus: SubtitleFileAccessStatus
    let captionSessionStatus: CaptionSessionStatus
    let speechAuthorizationStatus: SpeechAuthorizationStatus
    let relayConnectionStatus: RelayConnectionStatus
    let onLogEvent: (LogLevel, String, String) -> Void
    @State private var subtitleFileSettingsErrorMessage: String?

    private var captureBinding: Binding<Bool> {
        Binding(
            get: { audioInputController.isCaptureEnabled },
            set: { audioInputController.setCaptureEnabled($0) }
        )
    }

    private var automaticNoiseCalibrationBinding: Binding<Bool> {
        Binding(
            get: { audioInputController.isAutomaticNoiseCalibrationEnabled },
            set: { audioInputController.setAutomaticNoiseCalibrationEnabled($0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Panel(title: L10n.text("panel.session"), systemImage: "dot.radiowaves.left.and.right") {
                    VStack(alignment: .leading, spacing: 12) {
                        SessionStatusValue(status: captionSessionStatus)
                        SessionCaptureValue(isCapturing: audioInputController.isCapturing)
                        SpeechAuthorizationValue(status: speechAuthorizationStatus)
                        RelayConnectionValue(status: relayConnectionStatus)
                        SubtitleFileAccessValue(status: subtitleFileAccessStatus)
                    }
                }

                Panel(title: L10n.text("panel.audioInput"), systemImage: "mic", minHeight: 168) {
                    Toggle(L10n.text("audio.capture"), isOn: captureBinding)
                        .font(.caption)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!audioInputController.canToggleCapture)
                } content: {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(L10n.text("audio.source"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Button {
                                    audioInputController.refreshDevices()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.borderless)
                                .help(L10n.text("audio.rescanSources"))
                            }

                            AudioSourceMenu(
                                devices: audioInputController.devices,
                                selectedDeviceID: audioInputController.selectedDeviceID,
                                selectedDeviceName: audioInputController.selectedDeviceName,
                                isDisabled: audioInputController.devices.isEmpty
                            ) { deviceID in
                                audioInputController.selectDevice(id: deviceID)
                            }
                        }

                        AudioLevelMeter(levelState: audioInputController.levelState)

                        HStack {
                            Text(L10n.text("audio.automaticCalibration"))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Toggle(L10n.text("audio.automaticCalibration"), isOn: automaticNoiseCalibrationBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            PermissionRow(
                                title: L10n.text("audio.microphonePermission"),
                                state: audioInputController.microphonePermission.title,
                                tint: audioInputController.microphonePermission.tint
                            )
                        }

                        if let errorMessage = audioInputController.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Panel(title: L10n.text("panel.subtitleFiles"), systemImage: "folder") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(L10n.text("subtitle.storageLocation"))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(subtitleFileSettings.storageDirectorySummary)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(.head)
                                .help(subtitleFileSettings.storageDirectorySummary)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    openSubtitleStorageDirectoryInFinder()
                                }
                        }
                        .font(.subheadline)

                        HStack(spacing: 8) {
                            Button {
                                chooseSubtitleStorageDirectory()
                            } label: {
                                Label(L10n.text("subtitle.chooseFolder"), systemImage: "folder.badge.gearshape")
                                    .frame(maxWidth: .infinity)
                            }

                            Button {
                                clearSubtitleStorageDirectory()
                            } label: {
                                Image(systemName: "xmark")
                                    .frame(width: 24)
                            }
                            .disabled(subtitleFileSettings.storageDirectoryURL == nil)
                            .help(L10n.text("subtitle.clearStorageLocation"))
                        }

                        if let subtitleFileSettingsErrorMessage {
                            Text(subtitleFileSettingsErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(20)
            .frame(width: WindowLayout.controlSidebarWidth)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .frame(width: WindowLayout.controlSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            refreshSubtitleFileAccessStatus()
        }
        .onChange(of: subtitleFileSettings) {
            refreshSubtitleFileAccessStatus()
        }
        .alert(L10n.text("alert.microphonePermission.title"), isPresented: $audioInputController.isMicrophoneSettingsPromptPresented) {
            Button(L10n.text("common.cancel"), role: .cancel) {}
            Button(L10n.text("common.openSystemSettings")) {
                audioInputController.openMicrophoneSettingsAfterConfirmation()
            }
        } message: {
            Text(L10n.text("alert.microphonePermission.message"))
        }
    }

    private func chooseSubtitleStorageDirectory() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("subtitle.chooseStoragePanel.title")
        panel.prompt = L10n.text("common.choose")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let directoryURL = panel.url else {
            return
        }

        do {
            var updatedSettings = subtitleFileSettings
            try updatedSettings.setStorageDirectory(directoryURL)
            subtitleFileSettings = updatedSettings
            subtitleFileSettingsErrorMessage = nil
            onLogEvent(.info, L10n.text("log.subtitle.storageUpdated"), directoryURL.path(percentEncoded: false))
        } catch {
            let message = L10n.text("subtitle.storageSaveFailed", error.localizedDescription)
            subtitleFileSettingsErrorMessage = message
            onLogEvent(.error, L10n.text("log.subtitle.storageSaveFailed"), message)
        }
    }

    private func clearSubtitleStorageDirectory() {
        subtitleFileSettings.clearStorageDirectory()
        subtitleFileSettingsErrorMessage = nil
        onLogEvent(.info, L10n.text("log.subtitle.storageCleared"), L10n.text("subtitle.storage.notConfigured"))
    }

    private func openSubtitleStorageDirectoryInFinder() {
        guard let storageDirectoryURL = subtitleFileSettings.storageDirectoryURL else {
            return
        }

        let didStartAccessing = storageDirectoryURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                storageDirectoryURL.stopAccessingSecurityScopedResource()
            }
        }

        NSWorkspace.shared.open(storageDirectoryURL)
    }

    private func refreshSubtitleFileAccessStatus() {
        guard let storageDirectoryURL = subtitleFileSettings.storageDirectoryURL else {
            subtitleFileAccessStatus = .notConfigured
            return
        }

        let didStartAccessing = storageDirectoryURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                storageDirectoryURL.stopAccessingSecurityScopedResource()
            }
        }

        var isDirectory: ObjCBool = false
        let isReachableDirectory = FileManager.default.fileExists(
            atPath: storageDirectoryURL.path(percentEncoded: false),
            isDirectory: &isDirectory
        ) && isDirectory.boolValue

        subtitleFileAccessStatus = didStartAccessing && isReachableDirectory ? .authorized : .unavailable
    }
}

struct CaptionWorkspace: View {
    @Binding var sessionTitle: String
    @Binding var inputLanguage: InputLanguage
    let outputLanguages: [SpeechOutputLanguage]
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case sessionTitle
    }

    private var previewLanguages: [SpeechOutputLanguage] {
        outputLanguages.filter { language in
            language.id != inputLanguage.matchingOutputLanguageID
        }
    }

    private func dismissSessionTitleFocus() {
        if focusedField == .sessionTitle {
            focusedField = nil
        }
    }

    private func clearInitialFocus() {
        focusedField = nil

        DispatchQueue.main.async {
            if focusedField == nil {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(L10n.text("caption.previewTitle"))
                                .font(.title2.weight(.semibold))

                            StatusPill(
                                title: captionPreviewState.state.title,
                                systemImage: captionPreviewState.state.systemImage,
                                tint: captionPreviewState.state.tint
                            )
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Text(L10n.text("speech.inputLanguage"))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker(L10n.text("speech.inputLanguage"), selection: $inputLanguage) {
                                ForEach(InputLanguage.allCases) { language in
                                    Text(language.nativeName).tag(language)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.trailing, 8)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("session.title"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ClickFocusedTextField(
                            placeholder: L10n.text("session.title.placeholder"),
                            text: $sessionTitle
                        ) {
                            focusedField = nil
                        }
                        .focused($focusedField, equals: .sessionTitle)
                        .frame(height: 28)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: L10n.text("caption.live"), systemImage: "waveform")

                        LiveTranscriptCard(
                            languageName: inputLanguage.name,
                            languageNativeName: inputLanguage.transcriptNativeName,
                            text: captionPreviewState.liveTranscript(for: inputLanguage)
                        )

                        if case let .failed(message) = captionPreviewState.state {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: L10n.text("caption.preview"), systemImage: "captions.bubble")

                        VStack(spacing: 12) {
                            ForEach(previewLanguages) { language in
                                CaptionCard(
                                    languageName: language.name,
                                    languageNativeName: language.nativeName,
                                    text: captionPreviewState.finalCaptionText(
                                        for: language,
                                        inputLanguage: inputLanguage
                                    )
                                )
                            }
                        }
                    }

                }
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissSessionTitleFocus()
                }
                .padding(24)
                .frame(width: geometry.size.width, alignment: .leading)
            }
            .scrollIndicators(.visible)
        }
        .onAppear {
            clearInitialFocus()
        }
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

struct ProjectionCaptureSettingsInspector: View {
    let inputLanguage: InputLanguage
    let outputLanguages: [SpeechOutputLanguage]
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    let maximumWidth: Double
    @AppStorage("projectionCapture.languageID") private var projectionCaptureLanguageID = "zh-Hant"
    @AppStorage("projectionCapture.width") private var projectionCaptureWidth = 720.0
    @AppStorage("projectionCapture.height") private var projectionCaptureHeight = 180.0
    @AppStorage("projectionCapture.fontID") private var projectionCaptureFontID = ProjectionCaptionFontChoice.systemID
    @AppStorage("projectionCapture.fontSize") private var projectionCaptureFontSize = 32.0
    @AppStorage("projectionCapture.lineSpacing") private var projectionCaptureLineSpacing = 6.0
    @AppStorage("projectionCapture.appendsText") private var projectionCaptureAppendsText = false
    @AppStorage("projectionCapture.appendLineLimit") private var projectionCaptureAppendLineLimit = 3.0
    @AppStorage("projectionCapture.paddingHorizontal") private var projectionCapturePaddingHorizontal = 28.0

    private var selectedLanguageID: Binding<String> {
        Binding(
            get: { validatedLanguageID },
            set: { projectionCaptureLanguageID = $0 }
        )
    }

    private var width: Binding<Double> {
        Binding(
            get: { projectionCaptureWidth },
            set: { projectionCaptureWidth = clampedWidth($0) }
        )
    }

    private var height: Binding<Double> {
        Binding(
            get: { projectionCaptureHeight },
            set: { projectionCaptureHeight = clampedHeight($0) }
        )
    }

    private var selectedFontID: Binding<String> {
        Binding(
            get: { validatedFontID },
            set: { projectionCaptureFontID = $0 }
        )
    }

    private var fontSize: Binding<Double> {
        Binding(
            get: { projectionCaptureFontSize },
            set: { projectionCaptureFontSize = clampedFontSize($0) }
        )
    }

    private var lineSpacing: Binding<Double> {
        Binding(
            get: { projectionCaptureLineSpacing },
            set: { projectionCaptureLineSpacing = clampedLineSpacing($0) }
        )
    }

    private var paddingHorizontal: Binding<Double> {
        Binding(
            get: { projectionCapturePaddingHorizontal },
            set: { projectionCapturePaddingHorizontal = clampedPadding($0) }
        )
    }

    private var appendLineLimit: Binding<Double> {
        Binding(
            get: { projectionCaptureAppendLineLimit },
            set: { projectionCaptureAppendLineLimit = clampedAppendLineLimit($0) }
        )
    }

    private var validatedLanguageID: String {
        if outputLanguages.contains(where: { $0.id == projectionCaptureLanguageID }) {
            return projectionCaptureLanguageID
        }

        return outputLanguages.first?.id ?? projectionCaptureLanguageID
    }

    private var validatedFontID: String {
        if ProjectionCaptionFontChoice.availableChoices.contains(where: { $0.id == projectionCaptureFontID }) {
            return projectionCaptureFontID
        }

        return ProjectionCaptionFontChoice.systemID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ProjectionInspectorRow(title: L10n.text("caption.projectionLanguage")) {
                        Picker(L10n.text("caption.projectionLanguage"), selection: selectedLanguageID) {
                            ForEach(outputLanguages) { language in
                                Text(language.nativeName).tag(language.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ProjectionInspectorRow(title: L10n.text("caption.projectionAppendMode")) {
                        Toggle(L10n.text("caption.projectionAppendMode"), isOn: $projectionCaptureAppendsText)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .frame(height: 26, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .top, spacing: 12) {
                    ProjectionInspectorRow(title: L10n.text("caption.projectionFont")) {
                        Picker(L10n.text("caption.projectionFont"), selection: selectedFontID) {
                            ForEach(ProjectionCaptionFontChoice.availableChoices) { fontChoice in
                                Text(fontChoice.localizedName).tag(fontChoice.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 170, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ProjectionInspectorRow(title: L10n.text("caption.projectionFontSize")) {
                        ProjectionDimensionField(
                            value: fontSize,
                            range: WindowLayout.projectionCaptureMinimumFontSize...WindowLayout.projectionCaptureMaximumFontSize,
                            step: 2
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .top, spacing: 12) {
                    ProjectionInspectorRow(title: L10n.text("caption.projectionWidth")) {
                        ProjectionDimensionField(
                            value: width,
                            range: WindowLayout.projectionCaptureMinimumWidth...maximumWidth,
                            step: 20
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ProjectionInspectorRow(title: L10n.text("caption.projectionHeight")) {
                        ProjectionDimensionField(
                            value: height,
                            range: WindowLayout.projectionCaptureMinimumHeight...WindowLayout.projectionCaptureMaximumHeight,
                            step: 10
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .top, spacing: 12) {
                    ProjectionInspectorRow(title: L10n.text("caption.projectionLineSpacing")) {
                        ProjectionDimensionField(
                            value: lineSpacing,
                            range: WindowLayout.projectionCaptureMinimumLineSpacing...WindowLayout.projectionCaptureMaximumLineSpacing,
                            step: 1
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ProjectionInspectorRow(title: L10n.text("caption.projectionPaddingHorizontal")) {
                        ProjectionDimensionField(
                            value: paddingHorizontal,
                            range: WindowLayout.projectionCaptureMinimumPadding...WindowLayout.projectionCaptureMaximumPadding,
                            step: 2
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                ProjectionInspectorRow(title: L10n.text("caption.projectionAppendLineLimit")) {
                    ProjectionDimensionField(
                        value: appendLineLimit,
                        range: WindowLayout.projectionCaptureMinimumAppendLineLimit...WindowLayout.projectionCaptureMaximumAppendLineLimit,
                        step: 1,
                        unit: L10n.text("caption.projectionAppendLineLimitUnit")
                    )
                }

                HStack(spacing: 8) {
                    Button {
                        captionPreviewState.clearProjectionCaption()
                    } label: {
                        Text(L10n.text("caption.projectionClear"))
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        captionPreviewState.fillProjectionCaption()
                    } label: {
                        Text(L10n.text("caption.projectionFill"))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .frame(width: 330)
        .background(.regularMaterial)
        .onAppear {
            projectionCaptureWidth = clampedWidth(projectionCaptureWidth)
            projectionCaptureHeight = clampedHeight(projectionCaptureHeight)
            projectionCaptureFontID = validatedFontID
            projectionCaptureFontSize = clampedFontSize(projectionCaptureFontSize)
            projectionCaptureLineSpacing = clampedLineSpacing(projectionCaptureLineSpacing)
            projectionCapturePaddingHorizontal = clampedPadding(projectionCapturePaddingHorizontal)
            projectionCaptureAppendLineLimit = clampedAppendLineLimit(projectionCaptureAppendLineLimit)
        }
    }

    private var selectedOutputLanguage: SpeechOutputLanguage? {
        outputLanguages.first { $0.id == validatedLanguageID }
    }

    private func clampedWidth(_ value: Double) -> Double {
        min(max(value, WindowLayout.projectionCaptureMinimumWidth), maximumWidth)
    }

    private func clampedHeight(_ value: Double) -> Double {
        min(max(value, WindowLayout.projectionCaptureMinimumHeight), WindowLayout.projectionCaptureMaximumHeight)
    }

    private func clampedFontSize(_ value: Double) -> Double {
        min(max(value, WindowLayout.projectionCaptureMinimumFontSize), WindowLayout.projectionCaptureMaximumFontSize)
    }

    private func clampedLineSpacing(_ value: Double) -> Double {
        min(max(value, WindowLayout.projectionCaptureMinimumLineSpacing), WindowLayout.projectionCaptureMaximumLineSpacing)
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

@MainActor
final class ProjectionSettingsPanelPresenter: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let panelSize = NSSize(width: 330, height: 500)
    private let minimumPanelHeight: CGFloat = 320
    private let panelMargin: CGFloat = 12

    func show(
        inputLanguage: InputLanguage,
        outputLanguages: [SpeechOutputLanguage],
        captionPreviewState: SpeechCaptionPreviewState
    ) {
        let maximumWidth = Self.currentProjectionCaptureMaximumWidth()

        if let panel {
            panel.contentView = NSHostingView(
                rootView: ProjectionCaptureSettingsInspector(
                    inputLanguage: inputLanguage,
                    outputLanguages: outputLanguages,
                    captionPreviewState: captionPreviewState,
                    maximumWidth: maximumWidth
                )
            )
            positionPanelAvoidingProjectionCapture(panel)
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        panel.title = L10n.text("projectionSettings.title")
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: ProjectionCaptureSettingsInspector(
                inputLanguage: inputLanguage,
                outputLanguages: outputLanguages,
                captionPreviewState: captionPreviewState,
                maximumWidth: maximumWidth
            )
        )
        positionPanelAvoidingProjectionCapture(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    func close() {
        panel?.close()
        panel = nil
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }

    private static func currentProjectionCaptureMaximumWidth() -> Double {
        let window = currentMainWindow()

        return WindowLayout.projectionCaptureMaximumWidth(
            for: window?.contentLayoutRect.width ?? WindowLayout.minimumSize.width
        )
    }

    private static func currentMainWindow() -> NSWindow? {
        NSApp.windows.first { window in
            !(window is NSPanel) && window.isVisible
        } ?? NSApp.mainWindow ?? NSApp.keyWindow
    }

    private func positionPanelAvoidingProjectionCapture(_ panel: NSPanel) {
        guard let mainWindow = Self.currentMainWindow() else {
            panel.center()
            return
        }

        let screenFrame = mainWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? mainWindow.frame
        let projectionFrame = currentProjectionCaptureFrame(in: mainWindow)
        let panelHeight = preferredPanelHeight(avoiding: projectionFrame, on: screenFrame)
        let panelSize = NSSize(width: panelSize.width, height: panelHeight)
        panel.setContentSize(panelSize)

        let candidates = preferredPanelOrigins(
            for: panelSize,
            avoiding: projectionFrame,
            in: mainWindow,
            on: screenFrame
        )

        let panelOrigin = candidates.first { origin in
            let frame = NSRect(origin: origin, size: panelSize)
            return screenFrame.contains(frame) && !frame.intersects(projectionFrame)
        } ?? fallbackPanelOrigin(
            for: panelSize,
            avoiding: projectionFrame,
            on: screenFrame
        )

        panel.setFrame(NSRect(origin: panelOrigin, size: panelSize), display: true)
    }

    private func currentProjectionCaptureFrame(in window: NSWindow) -> NSRect {
        let contentFrame = window.contentLayoutRect
        let storedWidth = UserDefaults.standard.double(forKey: "projectionCapture.width")
        let storedHeight = UserDefaults.standard.double(forKey: "projectionCapture.height")
        let maximumWidth = WindowLayout.projectionCaptureMaximumWidth(for: contentFrame.width)
        let width = min(
            max(storedWidth == 0 ? 720 : storedWidth, WindowLayout.projectionCaptureMinimumWidth),
            maximumWidth
        )
        let height = min(
            max(storedHeight == 0 ? 180 : storedHeight, WindowLayout.projectionCaptureMinimumHeight),
            WindowLayout.projectionCaptureMaximumHeight
        )
        let x = contentFrame.minX + WindowLayout.projectionCaptureHorizontalPadding
        let y = contentFrame.maxY
            - WindowLayout.headerEstimatedHeight
            - WindowLayout.projectionCaptureVerticalPadding
            - height

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func preferredPanelHeight(avoiding projectionFrame: NSRect, on screenFrame: NSRect) -> CGFloat {
        let availableBelowProjection = projectionFrame.minY - screenFrame.minY - (panelMargin * 2)

        if availableBelowProjection >= minimumPanelHeight {
            return min(panelSize.height, availableBelowProjection)
        }

        return panelSize.height
    }

    private func preferredPanelOrigins(
        for panelSize: NSSize,
        avoiding projectionFrame: NSRect,
        in window: NSWindow,
        on screenFrame: NSRect
    ) -> [NSPoint] {
        let contentFrame = window.contentLayoutRect
        let preferredX = clamped(
            contentFrame.maxX - panelSize.width - 24,
            min: screenFrame.minX + panelMargin,
            max: screenFrame.maxX - panelSize.width - panelMargin
        )
        let sideY = clamped(
            projectionFrame.maxY - panelSize.height,
            min: screenFrame.minY + panelMargin,
            max: screenFrame.maxY - panelSize.height - panelMargin
        )

        return [
            NSPoint(x: preferredX, y: projectionFrame.minY - panelSize.height - panelMargin),
            NSPoint(x: projectionFrame.maxX + panelMargin, y: sideY),
            NSPoint(x: projectionFrame.minX - panelSize.width - panelMargin, y: sideY),
            NSPoint(x: preferredX, y: screenFrame.minY + panelMargin)
        ]
    }

    private func fallbackPanelOrigin(
        for panelSize: NSSize,
        avoiding projectionFrame: NSRect,
        on screenFrame: NSRect
    ) -> NSPoint {
        let belowY = min(
            projectionFrame.minY - panelSize.height - panelMargin,
            screenFrame.maxY - panelSize.height - panelMargin
        )

        return NSPoint(
            x: screenFrame.maxX - panelSize.width - panelMargin,
            y: max(screenFrame.minY + panelMargin, belowY)
        )
    }

    private func clamped(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        guard minimum <= maximum else {
            return minimum
        }

        return Swift.min(Swift.max(value, minimum), maximum)
    }
}

struct ProjectionInspectorRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            content
        }
    }
}

struct ProjectionInspectorInlineRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            content
        }
    }
}

struct ProjectionDimensionField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var unit = "pt"

    private var integerValue: Binding<Int> {
        Binding(
            get: { Int(value.rounded()) },
            set: { value = clamped(Double($0)) }
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField("", value: integerValue, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospacedDigit())
                .frame(width: 64)
                .onSubmit {
                    value = clamped(value)
                }

            Stepper(
                "",
                onIncrement: {
                    value = nextSteppedValue()
                },
                onDecrement: {
                    value = previousSteppedValue()
                }
            )
                .labelsHidden()

            if !unit.isEmpty {
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func nextSteppedValue() -> Double {
        let currentValue = clamped(value)
        let nextMultiple = ceil(currentValue / step) * step
        let steppedValue = isMultiple(currentValue) ? currentValue + step : nextMultiple
        return clamped(steppedValue)
    }

    private func previousSteppedValue() -> Double {
        let currentValue = clamped(value)
        let previousMultiple = floor(currentValue / step) * step
        let steppedValue = isMultiple(currentValue) ? currentValue - step : previousMultiple
        return clamped(steppedValue)
    }

    private func isMultiple(_ value: Double) -> Bool {
        abs(value.truncatingRemainder(dividingBy: step)) < 0.0001
    }
}

struct ProjectionCaptionFontChoice: Identifiable {
    static let systemID = "system"

    private static let commonChoices: [ProjectionCaptionFontChoice] = [
        ProjectionCaptionFontChoice(id: systemID, familyName: nil, localizedNameKey: "caption.projectionFont.system"),
        ProjectionCaptionFontChoice(id: "pingfang-tc", familyName: "PingFang TC", localizedNameKey: "caption.projectionFont.pingFangTC"),
        ProjectionCaptionFontChoice(id: "hiragino-sans", familyName: "Hiragino Sans", localizedNameKey: "caption.projectionFont.hiraginoSans"),
        ProjectionCaptionFontChoice(id: "apple-sd-gothic-neo", familyName: "Apple SD Gothic Neo", localizedNameKey: "caption.projectionFont.appleSDGothicNeo"),
        ProjectionCaptionFontChoice(id: "helvetica-neue", familyName: "Helvetica Neue", localizedNameKey: "caption.projectionFont.helveticaNeue")
    ]

    let id: String
    let familyName: String?
    let localizedNameKey: String

    var localizedName: String {
        L10n.text(localizedNameKey)
    }

    static var availableChoices: [ProjectionCaptionFontChoice] {
        let availableFamilies = Set(NSFontManager.shared.availableFontFamilies)
        return commonChoices.filter { choice in
            guard let familyName = choice.familyName else {
                return true
            }

            return availableFamilies.contains(familyName)
        }
    }

    static func choice(for id: String) -> ProjectionCaptionFontChoice {
        availableChoices.first { $0.id == id } ?? commonChoices[0]
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

struct ProjectionCaptionTextView: NSViewRepresentable {
    let text: String
    let font: NSFont
    let lineSpacing: CGFloat

    func makeNSView(context: Context) -> ProjectionCaptionDrawingView {
        ProjectionCaptionDrawingView()
    }

    func updateNSView(_ nsView: ProjectionCaptionDrawingView, context: Context) {
        nsView.text = text
        nsView.font = font
        nsView.lineSpacing = lineSpacing
    }
}

final class ProjectionCaptionDrawingView: NSView {
    var text: String = "" {
        didSet { needsDisplay = true }
    }

    var font: NSFont = .systemFont(ofSize: 32, weight: .semibold) {
        didSet { needsDisplay = true }
    }

    var lineSpacing: CGFloat = 6 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.alignment = .left

        let attributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraphStyle
            ]
        )

        let textBounds = attributedString.boundingRect(
            with: CGSize(width: bounds.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let drawHeight = min(ceil(textBounds.height), bounds.height)
        let drawRect = CGRect(
            x: bounds.minX,
            y: max(bounds.minY, bounds.maxY - drawHeight),
            width: bounds.width,
            height: drawHeight
        )

        attributedString.draw(
            with: drawRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
    }
}

private enum ProjectionCaptionTextTruncator {
    static func visibleSuffix(
        of text: String,
        fitting size: CGSize,
        font: NSFont,
        lineSpacing: CGFloat
    ) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty, size.width > 0, size.height > 0 else {
            return trimmedText
        }

        let tokens = wrappingTokens(in: trimmedText)

        if let wrappedText = wrappedText(tokens: tokens, fitting: size, font: font, lineSpacing: lineSpacing) {
            return wrappedText
        }

        for startIndex in tokens.indices.dropFirst() {
            guard tokens[startIndex] != " ", tokens[startIndex] != "\n" else {
                continue
            }

            let candidateTokens = Array(tokens[startIndex...])

            if let wrappedText = wrappedText(tokens: candidateTokens, fitting: size, font: font, lineSpacing: lineSpacing) {
                return wrappedText
            }
        }

        return characterTrimmedSuffix(
            of: trimmedText,
            fitting: size,
            font: font,
            lineSpacing: lineSpacing
        )
    }

    private static func characterTrimmedSuffix(
        of text: String,
        fitting size: CGSize,
        font: NSFont,
        lineSpacing: CGFloat
    ) -> String {
        let characterStartIndices = text.indices.dropFirst()

        for index in characterStartIndices {
            let candidate = String(text[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens = wrappingTokens(in: candidate)

            if let wrappedText = wrappedText(tokens: tokens, fitting: size, font: font, lineSpacing: lineSpacing) {
                return wrappedText
            }
        }

        return ""
    }

    private static func wrappedText(
        tokens: [String],
        fitting size: CGSize,
        font: NSFont,
        lineSpacing: CGFloat
    ) -> String? {
        let lines = wrappedLines(tokens: tokens, width: size.width, font: font)
        let height = measuredHeight(lineCount: lines.count, font: font, lineSpacing: lineSpacing)

        guard height <= size.height else {
            return nil
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func wrappedLines(
        tokens: [String],
        width: CGFloat,
        font: NSFont
    ) -> [String] {
        var lines: [String] = []
        var currentLine = ""

        for token in tokens {
            if token == "\n" {
                appendLine(currentLine, to: &lines)
                currentLine = ""
                continue
            }

            if token == " " {
                guard !currentLine.isEmpty else {
                    continue
                }

                let candidate = currentLine + token

                if measuredWidth(of: candidate, font: font) <= width {
                    currentLine = candidate
                } else {
                    appendLine(currentLine, to: &lines)
                    currentLine = ""
                }

                continue
            }

            if currentLine.isEmpty {
                appendToken(token, width: width, font: font, currentLine: &currentLine, lines: &lines)
                continue
            }

            let candidate = currentLine + token

            if measuredWidth(of: candidate, font: font) <= width {
                currentLine = candidate
            } else {
                appendLine(currentLine, to: &lines)
                currentLine = ""
                appendToken(token, width: width, font: font, currentLine: &currentLine, lines: &lines)
            }
        }

        appendLine(currentLine, to: &lines)
        return lines.isEmpty ? [""] : lines
    }

    private static func appendToken(
        _ token: String,
        width: CGFloat,
        font: NSFont,
        currentLine: inout String,
        lines: inout [String]
    ) {
        guard measuredWidth(of: token, font: font) > width else {
            currentLine = token
            return
        }

        for character in token {
            let fragment = String(character)

            if currentLine.isEmpty {
                currentLine = fragment
                continue
            }

            let candidate = currentLine + fragment

            if measuredWidth(of: candidate, font: font) <= width {
                currentLine = candidate
            } else {
                appendLine(currentLine, to: &lines)
                currentLine = fragment
            }
        }
    }

    private static func appendLine(_ line: String, to lines: inout [String]) {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        if !trimmedLine.isEmpty {
            lines.append(trimmedLine)
        }
    }

    private static func wrappingTokens(in text: String) -> [String] {
        var tokens: [String] = []
        var wordBuffer = ""
        var previousWasWhitespace = false

        func flushWordBuffer() {
            guard !wordBuffer.isEmpty else {
                return
            }

            tokens.append(wordBuffer)
            wordBuffer = ""
        }

        for character in text {
            if character.isNewline {
                flushWordBuffer()
                tokens.append("\n")
                previousWasWhitespace = false
                continue
            }

            if character.isWhitespace {
                flushWordBuffer()

                if !previousWasWhitespace {
                    tokens.append(" ")
                }

                previousWasWhitespace = true
                continue
            }

            previousWasWhitespace = false

            if character.isCJKWrappingCharacter {
                flushWordBuffer()
                tokens.append(String(character))
            } else {
                wordBuffer.append(character)
            }
        }

        flushWordBuffer()
        return tokens
    }

    private static func measuredWidth(of text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func measuredHeight(lineCount: Int, font: NSFont, lineSpacing: CGFloat) -> CGFloat {
        guard lineCount > 0 else {
            return 0
        }

        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        return (lineHeight * CGFloat(lineCount)) + (lineSpacing * CGFloat(max(0, lineCount - 1)))
    }
}

private extension Character {
    var isWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) }
    }

    var isNewline: Bool {
        unicodeScalars.allSatisfy { CharacterSet.newlines.contains($0) }
    }

    var isCJKWrappingCharacter: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x2EFF,
                 0x3000...0x303F,
                 0x3040...0x30FF,
                 0x3100...0x312F,
                 0x3130...0x318F,
                 0x31A0...0x31BF,
                 0x31C0...0x31EF,
                 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xAC00...0xD7AF,
                 0xF900...0xFAFF,
                 0xFF00...0xFFEF:
                return true
            default:
                return false
            }
        }
    }
}

struct ClickFocusedTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let onExitFocus: () -> Void

    func makeNSView(context: Context) -> MouseFocusedNSTextField {
        let textField = MouseFocusedNSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.font = .systemFont(ofSize: NSFont.systemFontSize(for: .regular), weight: .medium)
        textField.lineBreakMode = .byTruncatingTail
        textField.stringValue = text
        textField.onExitFocus = onExitFocus
        return textField
    }

    func updateNSView(_ nsView: MouseFocusedNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        nsView.placeholderString = placeholder
        nsView.onExitFocus = onExitFocus
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            text = textField.stringValue
        }
    }
}

final class MouseFocusedNSTextField: NSTextField {
    var onExitFocus: (() -> Void)?
    private var isHandlingMouseDown = false

    override var acceptsFirstResponder: Bool {
        isHandlingMouseDown
    }

    override func mouseDown(with event: NSEvent) {
        isHandlingMouseDown = true
        super.mouseDown(with: event)
        isHandlingMouseDown = false
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 48, 53:
            window?.makeFirstResponder(nil)
            onExitFocus?()
        default:
            super.keyDown(with: event)
        }
    }
}

struct StatusSidebar: View {
    let inputLanguage: InputLanguage
    let captionSessionStatus: CaptionSessionStatus
    @Binding var speechSettings: SpeechSettings
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    @Binding var speechAuthorizationStatus: SpeechAuthorizationStatus
    @Binding var relaySettings: RelaySettings
    @Binding var relayConnectionStatus: RelayConnectionStatus
    let recognizedCaptionCount: Int
    let relayLastPublishedAt: Date?
    let logEntries: [LogEntry]
    let onLogEvent: (LogLevel, String, String) -> Void
    @State private var projectionSettingsPanelPresenter = ProjectionSettingsPanelPresenter()
    @State private var isSpeechSettingsPresented = false
    @State private var isRelaySettingsPresented = false

    private var areProjectionSettingsLocked: Bool {
        captionSessionStatus.locksProjectionSettings
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Panel(title: L10n.text("projectionSettings.panelTitle"), systemImage: "rectangle.dashed") {
                    Button {
                        projectionSettingsPanelPresenter.show(
                            inputLanguage: inputLanguage,
                            outputLanguages: speechSettings.selectedOutputLanguages,
                            captionPreviewState: captionPreviewState
                        )
                    } label: {
                        Label(L10n.text("settings.open"), systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(areProjectionSettingsLocked)
                }

                Panel(title: "Speech", systemImage: "waveform.badge.magnifyingglass") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledValue(label: "Region", value: speechSettings.regionSummary)
                        LabeledValue(label: L10n.text("speech.inputLanguage"), value: inputLanguage.nativeName)
                        LabeledValue(label: L10n.text("speech.outputLanguages"), value: speechSettings.outputLanguageSummary)

                        Button {
                            isSpeechSettingsPresented = true
                        } label: {
                            Label(L10n.text("settings.open"), systemImage: "gearshape")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .sheet(isPresented: $isSpeechSettingsPresented) {
                    SpeechSettingsSheet(
                        settings: $speechSettings,
                        isPresented: $isSpeechSettingsPresented
                    ) { result in
                        speechAuthorizationStatus = .authorized
                        speechAuthorizationStatus.save()
                        onLogEvent(.info, L10n.text("log.speech.settingsTestSucceeded"), "Region \(result.region)")
                        testRelayConnectionAfterSpeechAuthorization()
                    } onFailure: { message in
                        speechAuthorizationStatus = .failed
                        speechAuthorizationStatus.save()
                        onLogEvent(.error, L10n.text("log.speech.settingsTestFailed"), message)
                    } onAuthorizationSettingsChanged: {
                        speechAuthorizationStatus = .initial(for: speechSettings)
                        speechAuthorizationStatus.save()
                    } onSpeechKeyChanged: {
                        relayConnectionStatus = .initial(for: relaySettings)
                        relayConnectionStatus.save()
                    }
                }

                Panel(title: "Relay", systemImage: "server.rack") {
                    VStack(alignment: .leading, spacing: 12) {
                        RelayURLValue(value: relaySettings.relayURLSummary)
                        LabeledValue(label: L10n.text("relay.roomName"), value: relaySettings.roomNameSummary)
                        LabeledValue(label: L10n.text("relay.trackNumber"), value: relaySettings.trackNumberSummary)
                        LabeledValue(label: L10n.text("relay.lastPublishedAt"), value: relayLastPublishedAtSummary)
                        LabeledValue(label: L10n.text("session.captionEvents"), value: "\(recognizedCaptionCount)")

                        Button {
                            isRelaySettingsPresented = true
                        } label: {
                            Label(L10n.text("settings.open"), systemImage: "gearshape")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .sheet(isPresented: $isRelaySettingsPresented) {
                    RelaySettingsSheet(
                        settings: $relaySettings,
                        speechSettings: speechSettings,
                        isPresented: $isRelaySettingsPresented
                    ) {
                        relayConnectionStatus = .testing
                        relayConnectionStatus.save()
                    } onConnectionTested: { result in
                        relayConnectionStatus = .connected
                        relayConnectionStatus.save()
                        onLogEvent(.info, L10n.text("log.relay.connectionTestSucceeded"), result.logDetail)
                    } onFailure: { message in
                        relayConnectionStatus = .failed
                        relayConnectionStatus.save()
                        onLogEvent(.error, L10n.text("log.relay.connectionTestFailed"), message)
                    } onSettingsChanged: {
                        relayConnectionStatus = .initial(for: relaySettings)
                        relayConnectionStatus.save()
                    }
                }

                Panel(title: L10n.text("panel.recentStatus"), systemImage: "clock.badge") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledValue(label: L10n.text("status.lastEvent"), value: recentStatusLastEventSummary)
                            .help(recentStatusLastEventHelp)
                        LabeledValue(label: L10n.text("status.warning"), value: "\(recentStatusWarningCount)")
                        LabeledValue(label: L10n.text("status.error"), value: "\(recentStatusErrorCount)")
                    }
                }
            }
            .padding(20)
            .frame(width: WindowLayout.statusSidebarWidth)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .frame(width: WindowLayout.statusSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: areProjectionSettingsLocked) {
            if areProjectionSettingsLocked {
                projectionSettingsPanelPresenter.close()
            }
        }
    }

    private var relayLastPublishedAtSummary: String {
        guard let relayLastPublishedAt else {
            return L10n.text("common.none")
        }

        return Self.relayLastPublishedAtFormatter.string(from: relayLastPublishedAt)
    }

    private var recentStatusLastEventSummary: String {
        guard let latestLogEntry = logEntries.first else {
            return L10n.text("common.none")
        }

        return "\(latestLogEntry.time) \(latestLogEntry.title)"
    }

    private var recentStatusLastEventHelp: String {
        guard let latestLogEntry = logEntries.first else {
            return L10n.text("common.none")
        }

        guard !latestLogEntry.detail.isEmpty else {
            return recentStatusLastEventSummary
        }

        return "\(recentStatusLastEventSummary)\n\(latestLogEntry.detail)"
    }

    private var recentStatusWarningCount: Int {
        logEntries.filter { $0.level == .warning }.count
    }

    private var recentStatusErrorCount: Int {
        logEntries.filter { $0.level == .error }.count
    }

    private static let relayLastPublishedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    private func testRelayConnectionAfterSpeechAuthorization() {
        guard relaySettings.isConfigured else {
            return
        }

        relayConnectionStatus = .testing
        relayConnectionStatus.save()

        let settingsToTest = relaySettings
        let speechKey = speechSettings.speechKey

        Task {
            do {
                let result = try await settingsToTest.testConnection(speechKey: speechKey)

                await MainActor.run {
                    relayConnectionStatus = .connected
                    relayConnectionStatus.save()
                    onLogEvent(.info, L10n.text("log.relay.connectionTestSucceeded"), result.logDetail)
                }
            } catch {
                let message = error.localizedDescription

                await MainActor.run {
                    relayConnectionStatus = .failed
                    relayConnectionStatus.save()
                    onLogEvent(.error, L10n.text("log.relay.connectionTestFailed"), message)
                }
            }
        }
    }
}

private struct RelayURLValue: View {
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("relay.url"))
                .foregroundStyle(.secondary)

            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .help(value)
        }
        .font(.subheadline)
    }
}
