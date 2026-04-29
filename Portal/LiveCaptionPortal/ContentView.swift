//
//  ContentView.swift
//  LiveCaptionPortal
//
//  Created by Hao Lee on 2026/4/26.
//

import SwiftUI

struct ContentView: View {
    @State private var inputLanguage = InputLanguage.mandarin
    @StateObject private var audioInputController = AudioInputController()
    @StateObject private var speechRecognitionController = SpeechRecognitionController()
    @State private var isCaptionSessionActive = false
    @State private var captionSessionStartedAt: Date?
    @State private var captionSessionElapsedTime: TimeInterval = 0
    @State private var speechSettings: SpeechSettings
    @State private var speechAuthorizationStatus: SpeechAuthorizationStatus
    @State private var shouldVerifySpeechAuthorizationOnLaunch: Bool
    @State private var subtitleFileSettings: SubtitleFileSettings
    @State private var subtitleExportSession: SubtitleExportSession?
    @State private var sessionTitle = ""
    @State private var subtitleFileAccessStatus = SubtitleFileAccessStatus.notConfigured
    @State private var isLogDrawerExpanded = false
    @State private var selectedLogLevel = LogLevel.all
    @State private var logEntries: [LogEntry] = []
    private let windowMinimumSize = WindowLayout.minimumSize

    init() {
        let speechSettings = SpeechSettings.load()
        let authorizationStatus = SpeechAuthorizationStatus.load(for: speechSettings)
        let shouldVerifySpeechAuthorizationOnLaunch = authorizationStatus == .authorized
        let subtitleFileSettings = SubtitleFileSettings.load()

        _speechSettings = State(initialValue: speechSettings)
        _speechAuthorizationStatus = State(
            initialValue: shouldVerifySpeechAuthorizationOnLaunch ? .verifying : authorizationStatus
        )
        _shouldVerifySpeechAuthorizationOnLaunch = State(initialValue: shouldVerifySpeechAuthorizationOnLaunch)
        _subtitleFileSettings = State(initialValue: subtitleFileSettings)
    }

    private var filteredLogEntries: [LogEntry] {
        guard selectedLogLevel != .all else {
            return logEntries
        }

        return logEntries.filter { $0.level == selectedLogLevel }
    }

    private func appendLog(level: LogLevel, title: String, detail: String) {
        logEntries.insert(
            LogEntry(time: LogClock.currentTimeString(), level: level, title: title, detail: detail),
            at: 0
        )
    }

    @MainActor
    private func verifySpeechAuthorizationOnLaunchIfNeeded() async {
        guard shouldVerifySpeechAuthorizationOnLaunch else {
            return
        }

        shouldVerifySpeechAuthorizationOnLaunch = false
        let settingsToTest = speechSettings

        do {
            let result = try await settingsToTest.testConnection()
            speechAuthorizationStatus = .authorized
            speechAuthorizationStatus.save()
            appendLog(level: .info, title: L10n.text("log.speech.reauthorizationSucceeded"), detail: "Region \(result.region)")
        } catch {
            let message = error.localizedDescription
            speechAuthorizationStatus = .failed
            speechAuthorizationStatus.save()
            appendLog(level: .error, title: L10n.text("log.speech.reauthorizationFailed"), detail: message)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HeaderView(
                    isCaptionSessionActive: isCaptionSessionActive,
                    captionSessionStartedAt: captionSessionStartedAt,
                    captionSessionElapsedTime: captionSessionElapsedTime,
                    canToggleCaptionSession: canToggleCaptionSession,
                    captionSessionDisabledReason: captionSessionDisabledReason,
                    onToggleCaptionSession: toggleCaptionSession
                )

                Divider()

                HStack(alignment: .top, spacing: 0) {
                    ControlSidebar(
                        audioInputController: audioInputController,
                        subtitleFileSettings: $subtitleFileSettings,
                        subtitleFileAccessStatus: $subtitleFileAccessStatus,
                        speechAuthorizationStatus: speechAuthorizationStatus,
                        recognizedCaptionCount: speechRecognitionController.recognizedCaptionCount
                    ) { level, title, detail in
                        appendLog(level: level, title: title, detail: detail)
                    }

                    Divider()

                    CaptionWorkspace(
                        sessionTitle: $sessionTitle,
                        inputLanguage: $inputLanguage,
                        outputLanguages: speechSettings.selectedOutputLanguages,
                        speechRecognitionController: speechRecognitionController
                    )

                    Divider()

                    StatusSidebar(
                        inputLanguage: inputLanguage,
                        speechSettings: $speechSettings,
                        speechAuthorizationStatus: $speechAuthorizationStatus
                    ) { level, title, detail in
                        appendLog(level: level, title: title, detail: detail)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.bottom, WindowLayout.logDrawerHeaderHeight)

            LogDrawer(
                isExpanded: $isLogDrawerExpanded,
                selectedLevel: $selectedLogLevel,
                entries: filteredLogEntries
            )
            .zIndex(100)
        }
        .frame(minWidth: windowMinimumSize.width, minHeight: windowMinimumSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            audioInputController.activate()
            await verifySpeechAuthorizationOnLaunchIfNeeded()
        }
        .onDisappear {
            finishCaptionSessionTiming()
            finishSubtitleExportSession()
            audioInputController.stopCapture()
            speechRecognitionController.stopRecognition()
        }
        .onChange(of: isCaptionSessionActive) {
            updateSpeechRecognition()
        }
        .onChange(of: audioInputController.isCapturing) {
            if !audioInputController.isCapturing {
                finishCaptionSessionTiming()
                finishSubtitleExportSession()
                isCaptionSessionActive = false
            } else {
                updateSpeechRecognition()
            }
        }
        .onChange(of: audioInputController.selectedDeviceID) {
            updateSpeechRecognition()
        }
        .onChange(of: inputLanguage) {
            updateSpeechRecognition()
        }
        .onChange(of: speechSettings) {
            updateSpeechRecognition()
        }
        .onChange(of: speechAuthorizationStatus) {
            updateSpeechRecognition()
        }
        .onChange(of: speechRecognitionController.latestCaptionEvent?.id) {
            appendLatestCaptionToSubtitleExportSession()
        }
    }

    private var canToggleCaptionSession: Bool {
        if isCaptionSessionActive {
            return true
        }

        return audioInputController.isCapturing && subtitleFileAccessStatus == .authorized
    }

    private var captionSessionDisabledReason: String? {
        if !audioInputController.isCapturing {
            return L10n.text("caption.disabled.enableCaptureFirst")
        }

        if subtitleFileAccessStatus != .authorized {
            return L10n.text("caption.disabled.configureSubtitleStorageFirst")
        }

        return nil
    }

    private func updateSpeechRecognition() {
        guard isCaptionSessionActive else {
            speechRecognitionController.stopRecognition(keepsCurrentTranscript: true)
            return
        }

        guard audioInputController.isCapturing else {
            speechRecognitionController.stopRecognition(keepsCurrentTranscript: true)
            return
        }

        speechRecognitionController.startRecognition(
            settings: speechSettings,
            inputLanguage: inputLanguage,
            audioDeviceID: audioInputController.selectedDeviceID,
            authorizationStatus: speechAuthorizationStatus
        )
    }

    private func toggleCaptionSession() {
        isCaptionSessionActive.toggle()

        if isCaptionSessionActive {
            captionSessionElapsedTime = 0
            let startedAt = Date()
            captionSessionStartedAt = startedAt
            beginSubtitleExportSession(startedAt: startedAt)
        } else {
            finishCaptionSessionTiming()
            finishSubtitleExportSession()
        }
    }

    private func finishCaptionSessionTiming() {
        guard let captionSessionStartedAt else {
            return
        }

        captionSessionElapsedTime = max(0, Date().timeIntervalSince(captionSessionStartedAt))
        self.captionSessionStartedAt = nil
    }

    private func beginSubtitleExportSession(startedAt: Date) {
        guard let storageDirectoryURL = subtitleFileSettings.storageDirectoryURL else {
            subtitleExportSession = nil
            appendLog(
                level: .warning,
                title: L10n.text("log.srt.outputNotCreated"),
                detail: L10n.text("subtitle.storage.notConfigured")
            )
            return
        }

        do {
            subtitleExportSession = try SubtitleExportSession(
                rootDirectoryURL: storageDirectoryURL,
                sessionTitle: sessionTitle,
                startedAt: startedAt,
                outputLanguages: speechSettings.selectedOutputLanguages
            )
            appendLog(
                level: .info,
                title: L10n.text("log.srt.outputPrepared"),
                detail: subtitleExportSession?.directoryURL.path(percentEncoded: false) ?? ""
            )
        } catch {
            subtitleExportSession = nil
            appendLog(level: .error, title: L10n.text("log.srt.createFolderFailed"), detail: error.localizedDescription)
        }
    }

    private func appendLatestCaptionToSubtitleExportSession() {
        guard var subtitleExportSession,
              let event = speechRecognitionController.latestCaptionEvent
        else {
            return
        }

        subtitleExportSession.append(event: event, inputLanguage: inputLanguage)
        self.subtitleExportSession = subtitleExportSession
    }

    private func finishSubtitleExportSession() {
        guard let subtitleExportSession else {
            return
        }

        do {
            let writtenFileURLs = try subtitleExportSession.writeFiles()
            let detail = writtenFileURLs.isEmpty
                ? L10n.text("srt.noCaptionEvents")
                : writtenFileURLs.map { $0.path(percentEncoded: false) }.joined(separator: "\n")
            appendLog(level: .info, title: L10n.text("log.srt.outputCompleted"), detail: detail)
        } catch {
            writeFallbackSubtitleFiles(for: subtitleExportSession, primaryError: error)
        }

        self.subtitleExportSession = nil
    }

    private func writeFallbackSubtitleFiles(
        for subtitleExportSession: SubtitleExportSession,
        primaryError: Error
    ) {
        do {
            let writtenFileURLs = try subtitleExportSession.writeFallbackFiles()
            let detail = fallbackSubtitleExportDetail(
                primaryError: primaryError,
                fallbackFileURLs: writtenFileURLs,
                fallbackDirectoryURL: subtitleExportSession.fallbackDirectoryURL
            )
            appendLog(level: .warning, title: L10n.text("log.srt.outputSavedToFallback"), detail: detail)
        } catch {
            appendLog(
                level: .error,
                title: L10n.text("log.srt.outputFailed"),
                detail: L10n.text("srt.fallbackFailed", primaryError.localizedDescription, error.localizedDescription)
            )
        }
    }

    private func fallbackSubtitleExportDetail(
        primaryError: Error,
        fallbackFileURLs: [URL],
        fallbackDirectoryURL: URL
    ) -> String {
        let fallbackLocation = fallbackFileURLs.isEmpty
            ? fallbackDirectoryURL.path(percentEncoded: false)
            : fallbackFileURLs.map { $0.path(percentEncoded: false) }.joined(separator: "\n")

        return L10n.text("srt.fallbackDetail", primaryError.localizedDescription, fallbackLocation)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
