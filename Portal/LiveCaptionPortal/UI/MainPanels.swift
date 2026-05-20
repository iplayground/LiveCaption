import AppKit
import SwiftUI

struct ControlSidebar: View {
    @ObservedObject var audioInputController: AudioInputController
    @Binding var subtitleFileSettings: SubtitleFileSettings
    @Binding var subtitleFileAccessStatus: SubtitleFileAccessStatus
    let captionSessionStatus: CaptionSessionStatus
    let areConfigurationControlsLocked: Bool
    let speechAuthorizationStatus: SpeechAuthorizationStatus
    let azureOpenAIConnectionStatus: AzureOpenAIConnectionStatus
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
                        AzureOpenAIConnectionValue(status: azureOpenAIConnectionStatus)
                        RelayConnectionValue(status: relayConnectionStatus)
                        SubtitleFileAccessValue(status: subtitleFileAccessStatus)
                    }
                }

                Panel(title: L10n.text("panel.audioInput"), systemImage: "mic", minHeight: 168) {
                    Toggle(L10n.text("audio.capture"), isOn: captureBinding)
                        .font(.caption)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(areConfigurationControlsLocked || !audioInputController.canToggleCapture)
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
                                .disabled(areConfigurationControlsLocked)
                                .help(L10n.text("audio.rescanSources"))
                            }

                            AudioSourceMenu(
                                devices: audioInputController.devices,
                                selectedDeviceID: audioInputController.selectedDeviceID,
                                selectedDeviceName: audioInputController.selectedDeviceName,
                                isDisabled: areConfigurationControlsLocked || audioInputController.devices.isEmpty
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
                                .disabled(areConfigurationControlsLocked)
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
                            .disabled(areConfigurationControlsLocked)

                            Button {
                                clearSubtitleStorageDirectory()
                            } label: {
                                Image(systemName: "xmark")
                                    .frame(width: 24)
                            }
                            .disabled(areConfigurationControlsLocked || subtitleFileSettings.storageDirectoryURL == nil)
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
        guard !areConfigurationControlsLocked else {
            return
        }

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
        guard !areConfigurationControlsLocked else {
            return
        }

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
    let processingInputLanguage: InputLanguage
    let areConfigurationControlsLocked: Bool
    let outputLanguages: [SpeechOutputLanguage]
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    @ObservedObject var pubSubCaptionReceiver: PubSubCaptionReceiver
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case sessionTitle
    }

    private var previewLanguages: [SpeechOutputLanguage] {
        outputLanguages.filter { language in
            inputLanguage != processingInputLanguage
                || language.id != processingInputLanguage.matchingOutputLanguageID
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
                            .disabled(areConfigurationControlsLocked)
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
                        .disabled(areConfigurationControlsLocked)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: L10n.text("caption.live"), systemImage: "waveform")

                        LiveTranscriptCard(
                            languageName: processingInputLanguage.name,
                            languageNativeName: processingInputLanguage.transcriptNativeName,
                            text: captionPreviewState.liveTranscript(for: processingInputLanguage)
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
                                        inputLanguage: processingInputLanguage
                                    )
                                )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: L10n.text("pubSub.caption"), systemImage: "dot.radiowaves.left.and.right")

                        PubSubCaptionCard(receiver: pubSubCaptionReceiver)
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
