import SwiftUI

extension ContentView {
func configureSpeechCallbacks() {
        speechRecognitionController.onCaptionCountChanged = { count in
            recognizedCaptionCount = count
        }

        speechRecognitionController.onCaptionEvent = { event in
            handleCaptionEvent(event)
        }

        speechRecognitionController.onLogEvent = { log in
            appendLog(log)
        }

        pubSubCaptionReceiver.onLogEvent = { log in
            appendLog(log)
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

    func handleRelayConnectionTested(_ result: RelayConnectionTestResult) {
        relayViewerAccessCode = result.viewerAccessCode
        publishPortalStatusToRelay("online")
        publishCaptionAvailabilityToRelayIfNeeded()
    }

    func handleCaptionEvent(_ event: RecognizedCaptionEvent) {
        guard event.processingGeneration == captionProcessingGeneration else {
            return
        }

        let sessionEvent = RecognizedCaptionEvent(
            id: event.id,
            text: event.text,
            translations: event.translations,
            offsetTicks: event.offsetTicks,
            durationTicks: event.durationTicks,
            sessionOffsetTicks: processingGenerationBaseOffsetTicks + event.offsetTicks,
            inputLanguage: event.inputLanguage,
            processingGeneration: event.processingGeneration,
            captionModes: event.captionModes
        )
        lastAcceptedSpeechSessionEndTicks = max(
            lastAcceptedSpeechSessionEndTicks,
            sessionEvent.sessionOffsetTicks + sessionEvent.durationTicks
        )

        if speechSettings.isAccurateCaptionEnabled {
            acceptedSpeechCaptionEventIDs.insert(sessionEvent.id)
        }
        appendCaptionToSubtitleExportSession(sessionEvent, mode: .fast)
        publishCaptionEventToRelay(sessionEvent, mode: .fast)

        Task { [accurateTranscriptionService] in
            await accurateTranscriptionService.transcribeAudio(for: sessionEvent)
        }
    }

    func handleOpenAITranscriptionResult(_ result: AzureOpenAIRealtimeTranscriptionResult) {
        Task {
            guard acceptedSpeechCaptionEventIDs.contains(result.captionEventID) else {
                return
            }

            guard let textResult = await openAITextResult(
                for: result.transcriptDrafts,
                inputLanguage: result.inputLanguage
            ) else {
                return
            }

            await MainActor.run {
                guard isCaptionSessionActive,
                      acceptedSpeechCaptionEventIDs.contains(result.captionEventID)
                else {
                    return
                }

                let event = RecognizedCaptionEvent(
                    text: textResult.sourceText,
                    translations: textResult.translations,
                    offsetTicks: result.offsetTicks,
                    durationTicks: result.durationTicks,
                    sessionOffsetTicks: result.sessionOffsetTicks,
                    inputLanguage: result.inputLanguage,
                    processingGeneration: result.processingGeneration,
                    captionModes: [
                        .accurate: CaptionModeResult(
                            providerID: CaptionQualityMode.accurate.providerID,
                            text: textResult.sourceText,
                            translations: textResult.translations
                        ),
                    ]
                )

                speechRecognitionController.captionPreviewState.setAccurateFinalCaption(
                    textResult.sourceText,
                    translations: textResult.translations,
                    offsetTicks: result.sessionOffsetTicks,
                    inputLanguage: result.inputLanguage,
                    processingGeneration: result.processingGeneration
                )
                appendCaptionToSubtitleExportSession(event, mode: .accurate)
                publishCaptionEventToRelay(event, mode: .accurate)
                acceptedSpeechCaptionEventIDs.remove(result.captionEventID)
            }
        }
    }

    func appendOpenAITranscriptionDiagnostic(_ diagnostic: AzureOpenAITranscriptionDiagnostic) {
        appendLog(
            level: diagnostic.level.logLevel,
            title: L10n.text("log.azureOpenAI.transcriptionDiagnostic"),
            detail: diagnostic.detail
        )
    }

    func appendOpenAITranslationDiagnostic(_ diagnostic: AzureOpenAIRealtimeTranslationDiagnostic) {
        appendLog(
            level: diagnostic.level.logLevel,
            title: L10n.text("log.azureOpenAI.translationDiagnostic"),
            detail: diagnostic.detail
        )
    }

    func startAccurateCaptionSessionIfNeeded(
        inputLanguage: InputLanguage,
        restartsTranslation: Bool = true
    ) async -> Bool {
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
            appendAccurateCaptionSkippedLog(detail: L10n.text("azureOpenAI.error.incompleteConfiguration"))
            return false
        }

        let configurations = accurateCaptionConfigurations(inputLanguage: inputLanguage)

        do {
            if restartsTranslation {
                try await accurateTranslationService.start(configuration: configurations.translation)
            }
            try await accurateTranscriptionService.start(configuration: configurations.transcription)
            appendAccurateCaptionStartedLog(endpointURLString: configurations.transcription.normalizedEndpointURLString)
            return true
        } catch {
            await handleAccurateCaptionStartFailure(error, restartsTranslation: restartsTranslation)
            return false
        }
    }

    func accurateCaptionConfigurations(
        inputLanguage: InputLanguage
    ) -> (
        translation: AzureOpenAITranslationConfig,
        transcription: AzureOpenAITranscriptionConfig
    ) {
        let targetLanguages = speechSettings.selectedOutputLanguages
        return (
            translation: speechSettings.azureOpenAIRealtimeConfiguration(outputLanguages: targetLanguages),
            transcription: speechSettings.azureOpenAIRealtimeTranscriptionConfiguration(
                inputLanguage: inputLanguage,
                speakerIdentity: speakerIdentityPromptValue(for: inputLanguage)
            )
        )
    }

    func appendAccurateCaptionStartedLog(endpointURLString: String) {
        appendLog(
            level: .info,
            title: L10n.text("log.azureOpenAI.realtimeStarted"),
            detail: endpointURLString
        )
    }

    func appendAccurateCaptionSkippedLog(detail: String) {
        appendLog(
            level: .warning,
            title: L10n.text("log.azureOpenAI.realtimeSkipped"),
            detail: detail
        )
    }

    func handleAccurateCaptionStartFailure(
        _ error: Error,
        restartsTranslation: Bool
    ) async {
        if restartsTranslation {
            await accurateTranslationService.stop()
        }
        await accurateTranscriptionService.stop()
        let detail = (error as? AzureOpenAIRealtimeTranslationError)?.diagnosticDescription
            ?? error.localizedDescription
        azureOpenAIConnectionStatus = .failed
        azureOpenAIConnectionStatus.save()
        appendLog(level: .error, title: L10n.text("log.azureOpenAI.realtimeFailed"), detail: detail)
    }

    func speakerIdentityPromptValue(for inputLanguage: InputLanguage) -> SpeakerIdentity? {
        guard inputLanguage == .english else {
            return nil
        }

        return speakerIdentity
    }

    func stopAccurateCaptionSession() {
        Task { [accurateTranslationService, accurateTranscriptionService] in
            await accurateTranslationService.stop()
            await accurateTranscriptionService.stop()
        }
    }

    func openAITextResult(
        for transcriptDrafts: [AccurateCaptionTranscriptDraft],
        inputLanguage: InputLanguage
    ) async -> AzureOpenAIRealtimeTranslationResult? {
        guard speechSettings.isAccurateCaptionEnabled else {
            return nil
        }

        return await accurateTranslationService.normalizeAndTranslate(
            transcriptDrafts: transcriptDrafts,
            inputLanguage: inputLanguage,
            phraseHints: speechSettings.phraseHints(for: inputLanguage),
            targetLanguageIDs: openAITranslationTargetLanguageIDs(inputLanguage: inputLanguage)
        )
    }

    func openAITranslationTargetLanguageIDs(inputLanguage: InputLanguage) -> Set<String> {
        let inputLanguageOutputID = inputLanguage.matchingOutputLanguageID
        return Set(speechSettings.selectedOutputLanguages.map(\.id))
            .filter { $0 != inputLanguageOutputID }
    }

    func missingOpenAITranslationLanguageIDs(
        in translations: [String: String],
        inputLanguage: InputLanguage
    ) -> [String] {
        openAITranslationTargetLanguageIDs(inputLanguage: inputLanguage)
            .filter { translations[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false }
            .sorted()
    }
}
