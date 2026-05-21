import SwiftUI

extension ContentView {
func handleDisappear() {
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

    func handleAudioCaptureStateChange() {
        if !audioInputController.isCapturing {
            if isCaptionSessionActive {
                captionSessionStatus = .stopping
                publishSessionStoppedToRelayIfNeeded()
            }
            finishCaptionSessionTiming()
            finishSubtitleExportSession()
            stopAccurateCaptionSession()
            isCaptionSessionActive = false
            captionProcessingPhase = .opening
        } else {
            updateSpeechRecognition()
        }

        refreshCaptionSessionReadiness()
    }

    var canToggleCaptionSession: Bool {
        if isCaptionSessionActive {
            return true
        }

        return canStartCaptionSession
    }

    var canEnterSpeakerCaptionMode: Bool {
        isCaptionSessionActive && captionProcessingPhase == .opening
    }

    var currentProcessingInputLanguage: InputLanguage {
        switch captionProcessingPhase {
        case .opening, .transitioningToSpeaker:
            .mandarin
        case .speaker:
            inputLanguage
        }
    }

    var canStartCaptionSession: Bool {
        audioInputController.isCapturing
            && speechAuthorizationStatus == .authorized
            && subtitleFileAccessStatus == .authorized
            && relayConnectionStatus == .connected
            && (!speechSettings.isAccurateCaptionEnabled || azureOpenAIConnectionStatus == .connected)
    }

    var captionSessionDisabledReason: String? {
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

    func updateSpeechRecognition() {
        guard isCaptionSessionActive else {
            speechRecognitionController.stopRecognition(keepsCurrentTranscript: true)
            return
        }

        guard audioInputController.isCapturing else {
            speechRecognitionController.stopRecognition(keepsCurrentTranscript: true)
            return
        }

        guard captionProcessingPhase != .transitioningToSpeaker else {
            speechRecognitionController.stopRecognition(keepsCurrentTranscript: true)
            return
        }

        speechRecognitionController.startRecognition(
            settings: speechSettings,
            inputLanguage: currentProcessingInputLanguage,
            audioDeviceID: audioInputController.selectedDeviceID,
            authorizationStatus: speechAuthorizationStatus,
            processingGeneration: captionProcessingGeneration
        )
    }

    func refreshCaptionSessionReadiness() {
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

    func refreshProjectionCaptureWindow() {
        projectionCaptureWindowPresenter.update(
            inputLanguage: isCaptionSessionActive ? currentProcessingInputLanguage : inputLanguage,
            outputLanguages: speechSettings.selectedOutputLanguages,
            captionPreviewState: speechRecognitionController.captionPreviewState,
            isPresented: !usesInlineProjectionCapture,
            areConfigurationControlsLocked: captionSessionStatus.locksConfigurationControls
        )
    }

    func toggleCaptionSession() {
        if isCaptionSessionActive {
            captionSessionStatus = .stopping
            isCaptionSessionActive = false
            publishSessionStoppedToRelayIfNeeded()
            finishCaptionSessionTiming()
            finishSubtitleExportSession()
            stopAccurateCaptionSession()
            pubSubCaptionReceiver.disconnect(keepsLatestCaption: true)
            sleepPreventionController.stopPreventingSleep()
            captionProcessingPhase = .opening
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
            acceptedSpeechCaptionEventIDs.removeAll()
            captionProcessingGeneration += 1
            processingGenerationBaseOffsetTicks = 0
            lastAcceptedSpeechSessionEndTicks = 0
            captionProcessingPhase = .opening
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
    func startCaptionSessionAfterPreparingOutput() async {
        guard await startAccurateCaptionSessionIfNeeded(inputLanguage: .mandarin) else {
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

    func enterSpeakerCaptionMode() {
        guard canEnterSpeakerCaptionMode else {
            return
        }

        Task { @MainActor in
            captionProcessingPhase = .transitioningToSpeaker
            processingGenerationBaseOffsetTicks = lastAcceptedSpeechSessionEndTicks
            captionProcessingGeneration += 1
            speechRecognitionController.stopRecognition(keepsCurrentTranscript: true)

            guard await startAccurateCaptionSessionIfNeeded(
                inputLanguage: inputLanguage,
                restartsTranslation: false
            ) else {
                isCaptionSessionActive = false
                publishSessionStoppedToRelayIfNeeded()
                finishCaptionSessionTiming()
                finishSubtitleExportSession()
                captionSessionStatus = .failed
                captionProcessingPhase = .opening
                pubSubCaptionReceiver.disconnect(keepsLatestCaption: true)
                sleepPreventionController.stopPreventingSleep()
                return
            }

            captionProcessingPhase = .speaker
            updateSpeechRecognition()
            appendLog(
                level: .info,
                title: L10n.text("log.captionProcessing.speakerModeStarted"),
                detail: inputLanguage.nativeName
            )
        }
    }

    func configureAudioCallbacks() {
        audioInputController.onAudioPCM16Chunk = { [accurateTranscriptionService] chunk in
            Task {
                await accurateTranscriptionService.appendPCM16Audio(chunk)
            }
        }
    }

    func finishCaptionSessionTiming() {
        guard let captionSessionStartedAt else {
            return
        }

        captionSessionElapsedTime = max(0, Date().timeIntervalSince(captionSessionStartedAt))
        self.captionSessionStartedAt = nil
    }

    func beginSubtitleExportSession(startedAt: Date) -> Bool {
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
}
