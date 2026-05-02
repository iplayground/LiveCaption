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
                                    text: captionPreviewState.captionText(
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
    @Binding var speechSettings: SpeechSettings
    @Binding var speechAuthorizationStatus: SpeechAuthorizationStatus
    @Binding var relaySettings: RelaySettings
    @Binding var relayConnectionStatus: RelayConnectionStatus
    let recognizedCaptionCount: Int
    let relayLastPublishedAt: Date?
    let logEntries: [LogEntry]
    let onLogEvent: (LogLevel, String, String) -> Void
    @State private var isSpeechSettingsPresented = false
    @State private var isRelaySettingsPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
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
