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
    @State private var captionSessionStatus = CaptionSessionStatus.notStarted
    @State private var captionSessionStartedAt: Date?
    @State private var captionSessionElapsedTime: TimeInterval = 0
    @State private var speechSettings: SpeechSettings
    @State private var speechAuthorizationStatus: SpeechAuthorizationStatus
    @State private var azureOpenAIConnectionStatus: AzureOpenAIConnectionStatus
    @State private var shouldVerifySpeechAuthorizationOnLaunch: Bool
    @State private var relaySettings: RelaySettings
    @State private var relayConnectionStatus: RelayConnectionStatus
    @State private var shouldVerifyRelayConnectionOnLaunch: Bool
    @State private var relayLastPublishedAt: Date?
    @State private var relayViewerAccessCode: String?
    @State private var subtitleFileSettings: SubtitleFileSettings
    @State private var subtitleExportSession: SubtitleExportSession?
    @State private var recognizedCaptionCount = 0
    @State private var relayPublishedCaptionCounts: [CaptionQualityMode: Int] = [:]
    @State private var sessionTitle = ""
    @State private var subtitleFileAccessStatus = SubtitleFileAccessStatus.notConfigured
    @State private var isLogDrawerExpanded = false
    @State private var selectedLogLevel = LogLevel.all
    @State private var logEntries: [LogEntry] = []
    @StateObject private var pubSubCaptionReceiver = PubSubCaptionReceiver()
    @State private var accurateCaptionService = AzureOpenAIRealtimeTranslationService()
    @State private var sleepPreventionController = SleepPreventionController()
    @State private var projectionCaptureWindowPresenter = ProjectionCaptureWindowPresenter()
    @AppStorage("projectionCapture.displayMode") private var projectionCaptureDisplayMode = ProjectionPreviewDisplayMode.inline.rawValue
    private let windowMinimumSize = WindowLayout.minimumSize
    private let relayPublishRetryLimit = 3
    private let maximumLogEntryCount = 300

    init() {
        let speechSettings = SpeechSettings.load()
        let authorizationStatus = SpeechAuthorizationStatus.load(for: speechSettings)
        let azureOpenAIConnectionStatus = AzureOpenAIConnectionStatus.load(for: speechSettings)
        let shouldVerifySpeechAuthorizationOnLaunch = authorizationStatus == .authorized
        let relaySettings = RelaySettings.load()
        let relayConnectionStatus = RelayConnectionStatus.load(for: relaySettings)
        let shouldVerifyRelayConnectionOnLaunch = relayConnectionStatus == .connected
        let subtitleFileSettings = SubtitleFileSettings.load()

        _speechSettings = State(initialValue: speechSettings)
        _speechAuthorizationStatus = State(
            initialValue: shouldVerifySpeechAuthorizationOnLaunch ? .verifying : authorizationStatus
        )
        _azureOpenAIConnectionStatus = State(initialValue: azureOpenAIConnectionStatus)
        _shouldVerifySpeechAuthorizationOnLaunch = State(initialValue: shouldVerifySpeechAuthorizationOnLaunch)
        _relaySettings = State(initialValue: relaySettings)
        _relayConnectionStatus = State(
            initialValue: shouldVerifyRelayConnectionOnLaunch ? .testing : relayConnectionStatus
        )
        _shouldVerifyRelayConnectionOnLaunch = State(initialValue: shouldVerifyRelayConnectionOnLaunch)
        _subtitleFileSettings = State(initialValue: subtitleFileSettings)
    }

    private var filteredLogEntries: [LogEntry] {
        guard selectedLogLevel != .all else {
            return logEntries
        }

        return logEntries.filter { $0.level == selectedLogLevel }
    }

    private var usesInlineProjectionCapture: Bool {
        ProjectionPreviewDisplayMode.mode(for: projectionCaptureDisplayMode) == .inline
    }

    private func appendLog(level: LogLevel, title: String, detail: String) {
        logEntries.insert(
            LogEntry(time: LogClock.currentTimeString(), level: level, title: title, detail: detail),
            at: 0
        )

        if logEntries.count > maximumLogEntryCount {
            logEntries.removeLast(logEntries.count - maximumLogEntryCount)
        }
    }

    private func appendLog(_ log: PortalWorkflowLog) {
        appendLog(level: log.level, title: log.title, detail: log.detail)
    }

    @MainActor
    private func verifySpeechAuthorizationOnLaunchIfNeeded() async {
        guard shouldVerifySpeechAuthorizationOnLaunch else {
            return
        }

        shouldVerifySpeechAuthorizationOnLaunch = false
        let result = await PortalLaunchVerifier.verifySpeechAuthorization(settings: speechSettings)
        speechAuthorizationStatus = result.status
        speechAuthorizationStatus.save()
        appendLog(result.log)
    }

    @MainActor
    private func verifyRelayConnectionOnLaunchIfNeeded() async {
        guard shouldVerifyRelayConnectionOnLaunch else {
            return
        }

        shouldVerifyRelayConnectionOnLaunch = false
        let result = await PortalLaunchVerifier.verifyRelayConnection(
            relaySettings: relaySettings,
            speechKey: speechSettings.speechKey
        )
        relayConnectionStatus = result.status
        relayViewerAccessCode = result.connectionTestResult?.viewerAccessCode
        relayConnectionStatus.save()
        appendLog(result.log)
    }

    var body: some View {
        ContentViewLayout(
            audioInputController: audioInputController,
            captionPreviewState: speechRecognitionController.captionPreviewState,
            sessionTitle: $sessionTitle,
            inputLanguage: $inputLanguage,
            subtitleFileSettings: $subtitleFileSettings,
            subtitleFileAccessStatus: $subtitleFileAccessStatus,
            speechSettings: $speechSettings,
            speechAuthorizationStatus: $speechAuthorizationStatus,
            azureOpenAIConnectionStatus: $azureOpenAIConnectionStatus,
            relaySettings: $relaySettings,
            relayConnectionStatus: $relayConnectionStatus,
            isLogDrawerExpanded: $isLogDrawerExpanded,
            selectedLogLevel: $selectedLogLevel,
            isCaptionSessionActive: isCaptionSessionActive,
            captionSessionStatus: captionSessionStatus,
            captionSessionStartedAt: captionSessionStartedAt,
            captionSessionElapsedTime: captionSessionElapsedTime,
            canToggleCaptionSession: canToggleCaptionSession,
            captionSessionDisabledReason: captionSessionDisabledReason,
            usesInlineProjectionCapture: usesInlineProjectionCapture,
            relayPublishedCaptionCounts: relayPublishedCaptionCounts,
            relayLastPublishedAt: relayLastPublishedAt,
            pubSubCaptionReceiver: pubSubCaptionReceiver,
            logEntries: logEntries,
            filteredLogEntries: filteredLogEntries,
            onToggleCaptionSession: toggleCaptionSession,
            onRelayConnectionTested: handleRelayConnectionTested
        ) { level, title, detail in
            appendLog(level: level, title: title, detail: detail)
        }
            .frame(minWidth: windowMinimumSize.width, minHeight: windowMinimumSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .background(KeyboardEventBlocker(isEnabled: captionSessionStatus.blocksKeyboardEvents))
            .background(
                WindowFrameRestorationBridge(
                    storageKey: "portal.mainWindow",
                    minimumSize: windowMinimumSize
                )
            )
            .task {
                audioInputController.activate()
                await verifySpeechAuthorizationOnLaunchIfNeeded()
                await verifyRelayConnectionOnLaunchIfNeeded()
            }
            .onAppear {
                configureAudioCallbacks()
                configureSpeechCallbacks()
                refreshProjectionCaptureWindow()
            }
            .onDisappear {
                projectionCaptureWindowPresenter.close()
                handleDisappear()
                NSApp.terminate(nil)
            }
            .onChange(of: isCaptionSessionActive) {
                updateSpeechRecognition()
            }
            .onChange(of: captionSessionStatus) {
                refreshProjectionCaptureWindow()
            }
            .onChange(of: audioInputController.isCapturing) {
                handleAudioCaptureStateChange()
            }
            .onChange(of: audioInputController.selectedDeviceID) {
                updateSpeechRecognition()
            }
            .onChange(of: inputLanguage) {
                speechRecognitionController.captionPreviewState.clearLivePreviewAfterInputLanguageChange()
                refreshProjectionCaptureWindow()
                updateSpeechRecognition()
            }
            .onChange(of: speechSettings) {
                refreshProjectionCaptureWindow()
                updateSpeechRecognition()
            }
            .onChange(of: projectionCaptureDisplayMode) {
                refreshProjectionCaptureWindow()
            }
            .onChange(of: speechAuthorizationStatus) {
                updateSpeechRecognition()
                refreshCaptionSessionReadiness()
            }
            .onChange(of: azureOpenAIConnectionStatus) {
                refreshCaptionSessionReadiness()
            }
            .onChange(of: subtitleFileAccessStatus) {
                refreshCaptionSessionReadiness()
            }
            .onChange(of: relayConnectionStatus) {
                refreshCaptionSessionReadiness()
            }
            .onChange(of: relaySettings) {
                relayLastPublishedAt = nil
                relayViewerAccessCode = nil
                relayPublishedCaptionCounts.removeAll()
                pubSubCaptionReceiver.disconnect()
            }
    }

    private func handleDisappear() {
        finishCaptionSessionTiming()
        finishSubtitleExportSession()
        stopAccurateCaptionSession()
        pubSubCaptionReceiver.disconnect()
        sleepPreventionController.stopPreventingSleep()
        audioInputController.stopCapture()
        speechRecognitionController.stopRecognition()
    }

    private func handleAudioCaptureStateChange() {
        if !audioInputController.isCapturing {
            if isCaptionSessionActive {
                captionSessionStatus = .stopping
            }
            finishCaptionSessionTiming()
            finishSubtitleExportSession()
            stopAccurateCaptionSession()
            isCaptionSessionActive = false
        } else {
            updateSpeechRecognition()
        }

        refreshCaptionSessionReadiness()
    }

    private var canToggleCaptionSession: Bool {
        if isCaptionSessionActive {
            return true
        }

        return canStartCaptionSession
    }

    private var canStartCaptionSession: Bool {
        audioInputController.isCapturing
            && speechAuthorizationStatus == .authorized
            && subtitleFileAccessStatus == .authorized
            && relayConnectionStatus == .connected
            && (!speechSettings.isAccurateCaptionEnabled || azureOpenAIConnectionStatus == .connected)
    }

    private var captionSessionDisabledReason: String? {
        if !audioInputController.isCapturing {
            return L10n.text("caption.disabled.enableCaptureFirst")
        }

        if speechAuthorizationStatus != .authorized {
            return L10n.text("caption.disabled.verifySpeechFirst")
        }

        if subtitleFileAccessStatus != .authorized {
            return L10n.text("caption.disabled.configureSubtitleStorageFirst")
        }

        if relayConnectionStatus != .connected {
            return L10n.text("caption.disabled.verifyRelayFirst")
        }

        if speechSettings.isAccurateCaptionEnabled, azureOpenAIConnectionStatus != .connected {
            return L10n.text("caption.disabled.verifyAzureOpenAIFirst")
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

    private func refreshCaptionSessionReadiness() {
        guard !isCaptionSessionActive else {
            return
        }

        guard canStartCaptionSession else {
            captionSessionStatus = .notStarted
            return
        }

        switch captionSessionStatus {
        case .notStarted, .ready:
            captionSessionStatus = .ready
        case .captioning, .stopping, .completed, .completedWithWarning, .failed:
            break
        }
    }

    private func refreshProjectionCaptureWindow() {
        projectionCaptureWindowPresenter.update(
            inputLanguage: inputLanguage,
            outputLanguages: speechSettings.selectedOutputLanguages,
            captionPreviewState: speechRecognitionController.captionPreviewState,
            isPresented: !usesInlineProjectionCapture,
            areConfigurationControlsLocked: captionSessionStatus.locksConfigurationControls
        )
    }

    private func toggleCaptionSession() {
        if isCaptionSessionActive {
            captionSessionStatus = .stopping
            isCaptionSessionActive = false
            finishCaptionSessionTiming()
            finishSubtitleExportSession()
            stopAccurateCaptionSession()
            pubSubCaptionReceiver.disconnect(keepsLatestCaption: true)
            sleepPreventionController.stopPreventingSleep()
        } else {
            guard canStartCaptionSession else {
                captionSessionStatus = .notStarted
                return
            }

            captionSessionElapsedTime = 0
            relayLastPublishedAt = nil
            relayPublishedCaptionCounts.removeAll()
            recognizedCaptionCount = 0
            pubSubCaptionReceiver.disconnect()
            speechRecognitionController.resetCaptionSessionMetrics()
            let startedAt = Date()
            captionSessionStartedAt = startedAt

            if beginSubtitleExportSession(startedAt: startedAt) {
                Task {
                    await startCaptionSessionAfterPreparingOutput()
                }
            } else {
                finishCaptionSessionTiming()
                sleepPreventionController.stopPreventingSleep()
                captionSessionStatus = .failed
            }
        }
    }

    @MainActor
    private func startCaptionSessionAfterPreparingOutput() async {
        guard await startAccurateCaptionSessionIfNeeded() else {
            subtitleExportSession = nil
            finishCaptionSessionTiming()
            sleepPreventionController.stopPreventingSleep()
            captionSessionStatus = .failed
            return
        }

        pubSubCaptionReceiver.connect(settings: relaySettings, viewerAccessCode: relayViewerAccessCode)
        sleepPreventionController.startPreventingSleep()
        captionSessionStatus = .captioning
        isCaptionSessionActive = true
    }

    private func configureAudioCallbacks() {
        audioInputController.onAudioPCM16Chunk = { [accurateCaptionService] chunk in
            Task {
                await accurateCaptionService.appendPCM16Audio(chunk)
            }
        }
    }

    private func finishCaptionSessionTiming() {
        guard let captionSessionStartedAt else {
            return
        }

        captionSessionElapsedTime = max(0, Date().timeIntervalSince(captionSessionStartedAt))
        self.captionSessionStartedAt = nil
    }

    private func beginSubtitleExportSession(startedAt: Date) -> Bool {
        guard let storageDirectoryURL = subtitleFileSettings.storageDirectoryURL else {
            subtitleExportSession = nil
            appendLog(
                level: .warning,
                title: L10n.text("log.srt.outputNotCreated"),
                detail: L10n.text("subtitle.storage.notConfigured")
            )
            return false
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
            return true
        } catch {
            subtitleExportSession = nil
            appendLog(level: .error, title: L10n.text("log.srt.createFolderFailed"), detail: error.localizedDescription)
            return false
        }
    }

    private func configureSpeechCallbacks() {
        speechRecognitionController.onCaptionCountChanged = { count in
            recognizedCaptionCount = count
        }

        speechRecognitionController.onCaptionEvent = { event in
            handleCaptionEvent(event)
        }
    }

    private func handleRelayConnectionTested(_ result: RelayConnectionTestResult) {
        relayViewerAccessCode = result.viewerAccessCode
    }

    private func handleCaptionEvent(_ event: RecognizedCaptionEvent) {
        Task {
            let enrichedEvent = await eventWithAccurateCaptionIfAvailable(event)
            await MainActor.run {
                appendCaptionToSubtitleExportSession(enrichedEvent)
                publishCaptionEventToRelay(enrichedEvent, mode: .fast)
                publishCaptionEventToRelay(enrichedEvent, mode: .accurate)
            }
        }
    }

    private func startAccurateCaptionSessionIfNeeded() async -> Bool {
        guard speechSettings.isAccurateCaptionEnabled else {
            return true
        }

        guard azureOpenAIConnectionStatus == .connected else {
            appendLog(
                level: .warning,
                title: L10n.text("log.azureOpenAI.realtimeSkipped"),
                detail: L10n.text("caption.disabled.verifyAzureOpenAIFirst")
            )
            return false
        }

        guard speechSettings.hasAzureOpenAIRealtimeConfiguration else {
            appendLog(
                level: .warning,
                title: L10n.text("log.azureOpenAI.realtimeSkipped"),
                detail: L10n.text("azureOpenAI.error.incompleteConfiguration")
            )
            return false
        }

        let inputLanguageOutputID = inputLanguage.matchingOutputLanguageID
        let targetLanguages = speechSettings.selectedOutputLanguages.filter { language in
            language.id != inputLanguageOutputID
        }
        let configuration = speechSettings.azureOpenAIRealtimeConfiguration(
            outputLanguages: targetLanguages
        )

        do {
            try await accurateCaptionService.start(configuration: configuration)
            appendLog(
                level: .info,
                title: L10n.text("log.azureOpenAI.realtimeStarted"),
                detail: configuration.normalizedEndpointURLString
            )
            return true
        } catch {
            azureOpenAIConnectionStatus = .failed
            azureOpenAIConnectionStatus.save()
            appendLog(
                level: .error,
                title: L10n.text("log.azureOpenAI.realtimeFailed"),
                detail: error.localizedDescription
            )
            return false
        }
    }

    private func stopAccurateCaptionSession() {
        Task {
            await accurateCaptionService.stop()
        }
    }

    private func eventWithAccurateCaptionIfAvailable(_ event: RecognizedCaptionEvent) async -> RecognizedCaptionEvent {
        guard speechSettings.isAccurateCaptionEnabled else {
            return event
        }

        let translations = await accurateCaptionService.takeTranslations()
        guard !translations.isEmpty else {
            return event
        }

        let inputLanguageOutputID = inputLanguage.matchingOutputLanguageID
        let selectedLanguageIDs = Set(speechSettings.selectedOutputLanguages.map(\.id))
        let requiredLanguageIDs = SpeechSettings.requiredOutputLanguageIDs
            .intersection(selectedLanguageIDs)
            .filter { $0 != inputLanguageOutputID }
        let missingRequiredLanguageIDs = requiredLanguageIDs.filter {
            translations[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        }
        guard missingRequiredLanguageIDs.isEmpty else {
            return event
        }

        let accurateText = translations[inputLanguageOutputID]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = CaptionModeResult(
            providerID: CaptionQualityMode.accurate.providerID,
            text: accurateText?.isEmpty == false ? accurateText! : event.text,
            translations: translations
        )

        return event.addingCaptionMode(.accurate, result: result)
    }

    private func appendCaptionToSubtitleExportSession(_ event: RecognizedCaptionEvent) {
        guard var subtitleExportSession else {
            return
        }

        subtitleExportSession.append(event: event, inputLanguage: inputLanguage)
        self.subtitleExportSession = subtitleExportSession
    }

    private func publishCaptionEventToRelay(_ event: RecognizedCaptionEvent, mode: CaptionQualityMode) {
        guard isCaptionSessionActive, relayConnectionStatus == .connected else {
            return
        }

        guard let relayInput = RelayCaptionPublishInput(
            event: event,
            mode: mode,
            inputLanguage: inputLanguage,
            outputLanguages: speechSettings.selectedOutputLanguages
        ) else {
            return
        }

        let settingsToPublish = relaySettings
        let speechKey = speechSettings.speechKey

        Task.detached {
            let outcome = await RelayCaptionPublisher.publish(
                relayInput,
                settings: settingsToPublish,
                speechKey: speechKey,
                retryLimit: relayPublishRetryLimit
            )

            await MainActor.run {
                if let publishedAt = outcome.publishedAt {
                    relayLastPublishedAt = publishedAt
                    relayPublishedCaptionCounts[mode, default: 0] += 1
                }

                outcome.logs.forEach(appendLog)

                if let connectionStatus = outcome.connectionStatus {
                    relayConnectionStatus = connectionStatus
                    relayConnectionStatus.save()
                }
            }
        }
    }

    private func finishSubtitleExportSession() {
        guard let subtitleExportSession else {
            if captionSessionStatus == .stopping {
                captionSessionStatus = .completed
            }
            sleepPreventionController.stopPreventingSleep()
            return
        }

        do {
            let writtenFileURLs = try subtitleExportSession.writeFiles()
            let detail = writtenFileURLs.isEmpty
                ? L10n.text("srt.noCaptionEvents")
                : writtenFileURLs.map { $0.path(percentEncoded: false) }.joined(separator: "\n")
            appendLog(level: .info, title: L10n.text("log.srt.outputCompleted"), detail: detail)
            captionSessionStatus = .completed
        } catch {
            writeFallbackSubtitleFiles(for: subtitleExportSession, primaryError: error)
        }

        self.subtitleExportSession = nil
        sleepPreventionController.stopPreventingSleep()
    }

    private func writeFallbackSubtitleFiles(
        for subtitleExportSession: SubtitleExportSession,
        primaryError: Error
    ) {
        do {
            let writtenFileURLs = try subtitleExportSession.writeFallbackFiles()
            let detail = subtitleExportSession.fallbackFailureDetail(
                primaryError: primaryError,
                fallbackFileURLs: writtenFileURLs
            )
            appendLog(level: .warning, title: L10n.text("log.srt.outputSavedToFallback"), detail: detail)
            captionSessionStatus = .completedWithWarning
        } catch {
            appendLog(
                level: .error,
                title: L10n.text("log.srt.outputFailed"),
                detail: L10n.text("srt.fallbackFailed", primaryError.localizedDescription, error.localizedDescription)
            )
            captionSessionStatus = .failed
        }
    }
}
