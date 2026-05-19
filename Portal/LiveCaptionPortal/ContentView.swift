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
    @State private var relayCaptionSessionID: String?
    @State private var lastPublishedCaptionAvailability: RelayCaptionAvailability?
    @State private var portalStatusHeartbeatTask: Task<Void, Never>?
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
    @State private var accurateTranslationService = AzureOpenAIRealtimeTranslationService()
    @State private var accurateTranscriptionService = AzureOpenAIRealtimeTranscriptionService()
    @State private var sleepPreventionController = SleepPreventionController()
    @State private var projectionCaptureWindowPresenter = ProjectionCaptureWindowPresenter()
    @AppStorage("projectionCapture.displayMode") private var projectionCaptureDisplayMode = ProjectionPreviewDisplayMode.inline.rawValue
    private let windowMinimumSize = WindowLayout.minimumSize
    private let relayPublishRetryLimit = 3
    private let maximumLogEntryCount = 300
    private let portalStatusHeartbeatInterval: Duration = .seconds(30)
    private static let relaySessionIDFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

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

    private static func relaySessionID(for date: Date) -> String {
        relaySessionIDFormatter.string(from: date)
            .replacingOccurrences(of: "Z", with: "")
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
                publishPortalStatusToRelay("online")
                publishCaptionAvailabilityToRelayIfNeeded()
            }
            .onAppear {
                configureAudioCallbacks()
                configureSpeechCallbacks()
                refreshPortalStatusHeartbeat()
                refreshProjectionCaptureWindow()
            }
            .onDisappear {
                projectionCaptureWindowPresenter.close()
                handleDisappear()
                NSApp.terminate(nil)
            }
            .onChange(of: isCaptionSessionActive) {
                updateSpeechRecognition()
                refreshPortalStatusHeartbeat()
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
                publishCaptionAvailabilityToRelayIfNeeded()
            }
            .onChange(of: azureOpenAIConnectionStatus) {
                updateSpeechRecognition()
                refreshCaptionSessionReadiness()
                publishCaptionAvailabilityToRelayIfNeeded()
            }
            .onChange(of: projectionCaptureDisplayMode) {
                refreshProjectionCaptureWindow()
            }
            .onChange(of: speechAuthorizationStatus) {
                updateSpeechRecognition()
                refreshCaptionSessionReadiness()
            }
            .onChange(of: subtitleFileAccessStatus) {
                refreshCaptionSessionReadiness()
            }
            .onChange(of: relayConnectionStatus) {
                refreshCaptionSessionReadiness()
                refreshPortalStatusHeartbeat()
            }
            .onChange(of: relaySettings) {
                relayLastPublishedAt = nil
                relayViewerAccessCode = nil
                relayCaptionSessionID = nil
                lastPublishedCaptionAvailability = nil
                relayPublishedCaptionCounts.removeAll()
                pubSubCaptionReceiver.disconnect()
                refreshPortalStatusHeartbeat()
            }
            .focusedSceneValue(
                \.portalEnvironmentTransferActions,
                 PortalEnvironmentTransferActions(
                    canImport: !isCaptionSessionActive,
                    importSettings: importPortalEnvironmentSettings,
                    exportSettings: exportPortalEnvironmentSettings
                 )
            )
    }

    private func exportPortalEnvironmentSettings() {
        speechSettings.save()
        relaySettings.save()

        guard let exportRequest = PortalEnvironmentTransferPanel.exportRequest() else {
            return
        }

        do {
            try PortalEnvironmentSettings(
                speechSettings: speechSettings,
                relaySettings: relaySettings
            )
            .writeConfiguration(to: exportRequest.fileURL, selection: exportRequest.selection)
            appendLog(level: .info, title: L10n.text("log.portalEnvironment.settingsExported"), detail: exportRequest.fileURL.path)
        } catch {
            PortalEnvironmentTransferPanel.showError(error.localizedDescription)
            appendLog(level: .error, title: L10n.text("log.portalEnvironment.settingsExportFailed"), detail: error.localizedDescription)
        }
    }

    private func importPortalEnvironmentSettings() {
        guard !isCaptionSessionActive else {
            return
        }

        guard let fileURL = PortalEnvironmentTransferPanel.importFileURL() else {
            return
        }

        do {
            let availableSections = try PortalEnvironmentSettings.availableImportSections(from: fileURL)
            guard let selectedSections = PortalEnvironmentTransferPanel.importSelection(
                availableSections: availableSections
            ) else {
                return
            }

            let importedSettings = try PortalEnvironmentSettings.importedConfiguration(
                from: fileURL,
                preservingLocalSettings: PortalEnvironmentSettings(
                    speechSettings: speechSettings,
                    relaySettings: relaySettings
                ),
                selection: selectedSections
            )
            speechSettings = importedSettings.speechSettings
            relaySettings = importedSettings.relaySettings
            speechSettings.save()
            relaySettings.save()
            if importedSettings.includedSections.includesAzureSpeechAuthorization {
                speechAuthorizationStatus = .initial(for: speechSettings)
                speechAuthorizationStatus.save()
            }
            if importedSettings.includedSections.includesAzureOpenAISettings {
                azureOpenAIConnectionStatus = .initial(for: speechSettings)
                azureOpenAIConnectionStatus.save()
            }
            if importedSettings.includedSections.includesRelayURL {
                relayConnectionStatus = .initial(for: relaySettings)
                relayConnectionStatus.save()
            }
            appendLog(level: .info, title: L10n.text("log.portalEnvironment.settingsImported"), detail: fileURL.path)
        } catch {
            PortalEnvironmentTransferPanel.showError(error.localizedDescription)
            appendLog(level: .error, title: L10n.text("log.portalEnvironment.settingsImportFailed"), detail: error.localizedDescription)
        }
    }

    private func handleDisappear() {
        stopPortalStatusHeartbeat()
        publishSessionStoppedToRelayIfNeeded()
        publishPortalStatusToRelay("offline")
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
                publishSessionStoppedToRelayIfNeeded()
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
            publishSessionStoppedToRelayIfNeeded()
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
            lastPublishedCaptionAvailability = nil
            relayPublishedCaptionCounts.removeAll()
            recognizedCaptionCount = 0
            pubSubCaptionReceiver.disconnect()
            speechRecognitionController.resetCaptionSessionMetrics()
            let startedAt = Date()
            captionSessionStartedAt = startedAt
            relayCaptionSessionID = Self.relaySessionID(for: startedAt)

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
        publishSessionStartedToRelay()
        publishCaptionAvailabilityToRelayIfNeeded()
    }

    private func configureAudioCallbacks() {
        audioInputController.onAudioPCM16Chunk = { [accurateTranscriptionService] chunk in
            Task {
                await accurateTranscriptionService.appendPCM16Audio(chunk)
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

        Task { [accurateTranscriptionService, accurateTranslationService] in
            await accurateTranscriptionService.setOnTranscription { result in
                Task { @MainActor in
                    handleOpenAITranscriptionResult(result)
                }
            }
            await accurateTranscriptionService.setOnDiagnostic { diagnostic in
                Task { @MainActor in
                    appendOpenAITranscriptionDiagnostic(diagnostic)
                }
            }
            await accurateTranslationService.setOnDiagnostic { diagnostic in
                Task { @MainActor in
                    appendOpenAITranslationDiagnostic(diagnostic)
                }
            }
        }
    }

    private func handleRelayConnectionTested(_ result: RelayConnectionTestResult) {
        relayViewerAccessCode = result.viewerAccessCode
        publishPortalStatusToRelay("online")
        publishCaptionAvailabilityToRelayIfNeeded()
    }

    private func handleCaptionEvent(_ event: RecognizedCaptionEvent) {
        appendCaptionToSubtitleExportSession(event, mode: .fast)
        publishCaptionEventToRelay(event, mode: .fast)

        Task { [accurateTranscriptionService] in
            await accurateTranscriptionService.transcribeAudio(for: event)
        }
    }

    private func handleOpenAITranscriptionResult(_ result: AzureOpenAIRealtimeTranscriptionResult) {
        Task {
            guard let textResult = await openAITextResult(for: result.transcriptDrafts) else {
                return
            }

            await MainActor.run {
                guard isCaptionSessionActive else {
                    return
                }

                let event = RecognizedCaptionEvent(
                    text: textResult.sourceText,
                    translations: textResult.translations,
                    offsetTicks: result.offsetTicks,
                    durationTicks: result.durationTicks,
                    captionModes: [
                        .accurate: CaptionModeResult(
                            providerID: CaptionQualityMode.accurate.providerID,
                            text: textResult.sourceText,
                            translations: textResult.translations
                        )
                    ]
                )

                speechRecognitionController.captionPreviewState.setAccurateFinalCaption(
                    textResult.sourceText,
                    translations: textResult.translations,
                    offsetTicks: result.offsetTicks
                )
                appendCaptionToSubtitleExportSession(event, mode: .accurate)
                publishCaptionEventToRelay(event, mode: .accurate)
            }
        }
    }

    private func appendOpenAITranscriptionDiagnostic(_ diagnostic: AzureOpenAIRealtimeTranscriptionDiagnostic) {
        appendLog(
            level: diagnostic.level.logLevel,
            title: L10n.text("log.azureOpenAI.transcriptionDiagnostic"),
            detail: diagnostic.detail
        )
    }

    private func appendOpenAITranslationDiagnostic(_ diagnostic: AzureOpenAIRealtimeTranslationDiagnostic) {
        appendLog(
            level: diagnostic.level.logLevel,
            title: L10n.text("log.azureOpenAI.translationDiagnostic"),
            detail: diagnostic.detail
        )
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
        let translationConfiguration = speechSettings.azureOpenAIRealtimeConfiguration(
            outputLanguages: targetLanguages
        )
        let transcriptionConfiguration = speechSettings.azureOpenAIRealtimeTranscriptionConfiguration(inputLanguage: inputLanguage)

        do {
            try await accurateTranslationService.start(configuration: translationConfiguration)
            try await accurateTranscriptionService.start(configuration: transcriptionConfiguration)
            appendLog(
                level: .info,
                title: L10n.text("log.azureOpenAI.realtimeStarted"),
                detail: transcriptionConfiguration.normalizedEndpointURLString
            )
            return true
        } catch {
            await accurateTranslationService.stop()
            await accurateTranscriptionService.stop()
            let detail = (error as? AzureOpenAIRealtimeTranslationError)?.diagnosticDescription
                ?? error.localizedDescription
            azureOpenAIConnectionStatus = .failed
            azureOpenAIConnectionStatus.save()
            appendLog(
                level: .error,
                title: L10n.text("log.azureOpenAI.realtimeFailed"),
                detail: detail
            )
            return false
        }
    }

    private func stopAccurateCaptionSession() {
        Task { [accurateTranslationService, accurateTranscriptionService] in
            await accurateTranslationService.stop()
            await accurateTranscriptionService.stop()
        }
    }

    private func openAITextResult(for transcriptDrafts: [AccurateCaptionTranscriptDraft]) async -> AzureOpenAIRealtimeTranslationResult? {
        guard speechSettings.isAccurateCaptionEnabled else {
            return nil
        }

        return await accurateTranslationService.normalizeAndTranslate(
            transcriptDrafts: transcriptDrafts,
            inputLanguage: inputLanguage,
            phraseHints: speechSettings.phraseHints(for: inputLanguage),
            targetLanguageIDs: openAITranslationTargetLanguageIDs()
        )
    }

    private func openAITranslationTargetLanguageIDs() -> Set<String> {
        let inputLanguageOutputID = inputLanguage.matchingOutputLanguageID
        return Set(speechSettings.selectedOutputLanguages.map(\.id))
            .filter { $0 != inputLanguageOutputID }
    }

    private func missingOpenAITranslationLanguageIDs(in translations: [String: String]) -> [String] {
        openAITranslationTargetLanguageIDs()
            .filter { translations[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false }
            .sorted()
    }

    private func appendCaptionToSubtitleExportSession(_ event: RecognizedCaptionEvent, mode: CaptionQualityMode) {
        guard var subtitleExportSession else {
            return
        }

        subtitleExportSession.append(event: event, inputLanguage: inputLanguage, mode: mode)
        self.subtitleExportSession = subtitleExportSession
    }

    private func publishCaptionEventToRelay(_ event: RecognizedCaptionEvent, mode: CaptionQualityMode) {
        guard isCaptionSessionActive,
              relayConnectionStatus == .connected,
              let relayCaptionSessionID else {
            return
        }

        if mode == .accurate {
            let translations = event.captionModes[mode]?.translations ?? [:]
            let missingLanguageIDs = missingOpenAITranslationLanguageIDs(in: translations)
            guard missingLanguageIDs.isEmpty else {
                appendOpenAITranslationDiagnostic(
                    AzureOpenAIRealtimeTranslationDiagnostic(
                        level: .warning,
                        detail: [
                            "phase=relaySkipped",
                            "reason=missingTranslations",
                            "missingLanguages=\(missingLanguageIDs.joined(separator: ","))",
                        ].joined(separator: "; ")
                    )
                )
                return
            }
        }

        guard let relayInput = RelayCaptionPublishInput(
            event: event,
            mode: mode,
            sessionID: relayCaptionSessionID,
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

    private func publishPortalStatusToRelay(_ status: String) {
        guard relayConnectionStatus == .connected else {
            return
        }

        let settingsToPublish = relaySettings
        let speechKey = speechSettings.speechKey
        Task.detached {
            _ = try? await settingsToPublish.publishPortalStatus(status, speechKey: speechKey)
        }
    }

    private func refreshPortalStatusHeartbeat() {
        guard relayConnectionStatus == .connected,
              !isCaptionSessionActive else {
            stopPortalStatusHeartbeat()
            return
        }
        startPortalStatusHeartbeat()
    }

    private func startPortalStatusHeartbeat() {
        guard portalStatusHeartbeatTask == nil else {
            return
        }
        portalStatusHeartbeatTask?.cancel()
        portalStatusHeartbeatTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: portalStatusHeartbeatInterval)
                guard !Task.isCancelled else {
                    return
                }
                let settingsToPublish = await MainActor.run {
                    relaySettings
                }
                let speechKey = await MainActor.run {
                    speechSettings.speechKey
                }
                _ = try? await settingsToPublish.markPortalActivity(speechKey: speechKey)
            }
        }
    }

    private func stopPortalStatusHeartbeat() {
        portalStatusHeartbeatTask?.cancel()
        portalStatusHeartbeatTask = nil
    }

    private func publishSessionStartedToRelay() {
        guard relayConnectionStatus == .connected,
              let relayCaptionSessionID else {
            return
        }

        let settingsToPublish = relaySettings
        let speechKey = speechSettings.speechKey
        Task.detached {
            _ = try? await settingsToPublish.publishSessionStatus(
                "started",
                sessionID: relayCaptionSessionID,
                speechKey: speechKey
            )
        }
    }

    private func publishSessionStoppedToRelayIfNeeded() {
        guard relayConnectionStatus == .connected,
              let relayCaptionSessionID else {
            return
        }

        self.relayCaptionSessionID = nil
        let settingsToPublish = relaySettings
        let speechKey = speechSettings.speechKey
        Task.detached {
            _ = try? await settingsToPublish.publishSessionStatus(
                "stopped",
                sessionID: relayCaptionSessionID,
                speechKey: speechKey
            )
        }
    }

    private func publishCaptionAvailabilityToRelayIfNeeded() {
        guard relayConnectionStatus == .connected else {
            return
        }

        let settingsToPublish = relaySettings
        let speechKey = speechSettings.speechKey
        let sessionID = relayCaptionSessionID
        let modes = availableCaptionModesForRelay()
        let languages = speechSettings.selectedOutputLanguages
        let availability = RelayCaptionAvailability(
            sessionID: sessionID,
            captionModes: modes,
            languages: languages
        )
        guard availability != lastPublishedCaptionAvailability else {
            return
        }
        lastPublishedCaptionAvailability = availability
        Task.detached {
            _ = try? await settingsToPublish.publishCaptionAvailability(
                sessionID: sessionID,
                captionModes: modes,
                languages: languages,
                speechKey: speechKey
            )
        }
    }

    private func availableCaptionModesForRelay() -> [CaptionQualityMode] {
        if speechSettings.isAccurateCaptionEnabled && azureOpenAIConnectionStatus == .connected {
            return [.fast, .accurate]
        }
        return [.fast]
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
                : L10n.text(
                    "srt.outputSummary",
                    writtenFileURLs.count,
                    subtitleExportSession.directoryURL.path(percentEncoded: false)
                )
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

private struct RelayCaptionAvailability: Equatable {
    let sessionID: String?
    let captionModeIDs: [String]
    let languageIDs: [String]

    init(
        sessionID: String?,
        captionModes: [CaptionQualityMode],
        languages: [SpeechOutputLanguage]
    ) {
        self.sessionID = sessionID
        captionModeIDs = captionModes.map(\.rawValue)
        languageIDs = languages.map(\.id)
    }
}

private extension AzureOpenAIRealtimeTranscriptionDiagnostic.Level {
    var logLevel: LogLevel {
        switch self {
        case .info:
            .info
        case .warning:
            .warning
        case .error:
            .error
        }
    }
}

private extension AzureOpenAIRealtimeTranslationDiagnostic.Level {
    var logLevel: LogLevel {
        switch self {
        case .warning:
            .warning
        case .error:
            .error
        }
    }
}
