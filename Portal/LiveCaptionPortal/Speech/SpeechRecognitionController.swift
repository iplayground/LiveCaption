import SwiftUI
import Combine
import MicrosoftCognitiveServicesSpeech

@MainActor
final class SpeechRecognitionController: ObservableObject {
    let captionPreviewState = SpeechCaptionPreviewState()
    var onCaptionEvent: ((RecognizedCaptionEvent) -> Void)?
    var onCaptionCountChanged: ((Int) -> Void)?
    var onLogEvent: ((PortalWorkflowLog) -> Void)?

    private static let interimUpdateInterval: TimeInterval = 1.0 / 12.0
    private static let phraseListWeight = 2.0
    private var recognizer: SPXTranslationRecognizer?
    private var activeRequest: SpeechRecognitionRequest?
    private var recognizedCaptionCount = 0

}

extension SpeechRecognitionController {
    func resetCaptionSessionMetrics() {
        recognizedCaptionCount = 0
        onCaptionCountChanged?(recognizedCaptionCount)
    }

    func startRecognition(
        settings: SpeechSettings,
        inputLanguage: InputLanguage,
        audioDeviceID: String?,
        authorizationStatus: SpeechAuthorizationStatus,
        processingGeneration: Int
    ) {
        guard let request = makeRecognitionRequest(
            settings: settings,
            inputLanguage: inputLanguage,
            audioDeviceID: audioDeviceID,
            authorizationStatus: authorizationStatus,
            processingGeneration: processingGeneration
        ) else {
            return
        }

        guard request != activeRequest || recognizer == nil else {
            return
        }

        stopRecognition(resetTranscript: false)
        activeRequest = request

        do {
            let translationConfiguration = try SPXSpeechTranslationConfiguration(
                subscription: request.speechKey,
                region: request.region
            )

            translationConfiguration.speechRecognitionLanguage = inputLanguage.speechLocale
            translationConfiguration.setPropertyTo("Time", by: SPXPropertyId(rawValue: 9_004)!)
            translationConfiguration.setPropertyTo(
                "\(settings.sentenceSilenceTimeoutMilliseconds)",
                by: SPXPropertyId(rawValue: 9_002)!
            )
            request.outputLanguageIDs
                .filter { $0 != inputLanguage.matchingOutputLanguageID }
                .forEach { translationConfiguration.addTargetLanguage($0) }

            guard let audioConfiguration = SPXAudioConfiguration(microphone: audioDeviceID) else {
                throw SpeechRecognitionError.audioConfigurationFailed
            }

            let translationRecognizer = try SPXTranslationRecognizer(
                speechTranslationConfiguration: translationConfiguration,
                audioConfiguration: audioConfiguration
            )

            applyPhraseHints(request.phraseHints, to: translationRecognizer)
            configureEventHandlers(
                for: translationRecognizer,
                inputLanguage: inputLanguage,
                processingGeneration: request.processingGeneration
            )

            try translationRecognizer.startContinuousRecognition()

            recognizer = translationRecognizer
            captionPreviewState.setListening()
        } catch {
            activeRequest = nil
            recognizer = nil
            captionPreviewState.setFailure(error.localizedDescription)
        }
    }

    private func makeRecognitionRequest(
        settings: SpeechSettings,
        inputLanguage: InputLanguage,
        audioDeviceID: String?,
        authorizationStatus: SpeechAuthorizationStatus,
        processingGeneration: Int
    ) -> SpeechRecognitionRequest? {
        let region = settings.region.trimmingCharacters(in: .whitespacesAndNewlines)
        let speechKey = settings.speechKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard validateAuthorizationStatus(authorizationStatus),
              validateAuthorizationMaterial(region: region, speechKey: speechKey),
              let audioDeviceID = validatedAudioDeviceID(audioDeviceID)
        else {
            return nil
        }

        return SpeechRecognitionRequest(
            region: region,
            speechKey: speechKey,
            inputLocale: inputLanguage.speechLocale,
            audioDeviceID: audioDeviceID,
            outputLanguageIDs: settings.selectedOutputLanguages.map(\.id).sorted(),
            phraseHints: settings.phraseHints(for: inputLanguage),
            sentenceSilenceTimeoutMilliseconds: settings.sentenceSilenceTimeoutMilliseconds,
            processingGeneration: processingGeneration
        )
    }

    private func validateAuthorizationStatus(_ authorizationStatus: SpeechAuthorizationStatus) -> Bool {
        guard authorizationStatus == .authorized else {
            stopRecognition(resetTranscript: false)
            captionPreviewState.setFailure(L10n.text("speechRecognition.error.notAuthorized"))
            return false
        }

        return true
    }

    private func validateAuthorizationMaterial(region: String, speechKey: String) -> Bool {
        guard !region.isEmpty, !speechKey.isEmpty else {
            stopRecognition(resetTranscript: false)
            captionPreviewState.setFailure(L10n.text("speechRecognition.error.missingRegionOrKey"))
            return false
        }

        return true
    }

    private func validatedAudioDeviceID(_ audioDeviceID: String?) -> String? {
        guard let audioDeviceID, !audioDeviceID.isEmpty else {
            stopRecognition(resetTranscript: false)
            captionPreviewState.setFailure(L10n.text("speechRecognition.error.noAudioSourceSelected"))
            return nil
        }

        return audioDeviceID
    }

    private func applyPhraseHints(_ phraseHints: [String], to recognizer: SPXTranslationRecognizer) {
        guard !phraseHints.isEmpty,
              let phraseList = SPXPhraseListGrammar(recognizer: recognizer)
        else {
            return
        }

        phraseHints.forEach { phraseList.addPhrase($0) }
        phraseList.setWeight(Self.phraseListWeight)
    }

    func stopRecognition(keepsCurrentTranscript: Bool = false) {
        stopRecognition(resetTranscript: !keepsCurrentTranscript)
    }

    private func stopRecognition(resetTranscript: Bool) {
        if let recognizer {
            try? recognizer.stopContinuousRecognition()
        }

        recognizer = nil
        activeRequest = nil
        captionPreviewState.setIdle()

        if resetTranscript {
            captionPreviewState.resetTranscript()
            recognizedCaptionCount = 0
            onCaptionCountChanged?(recognizedCaptionCount)
        }
    }

    private func configureEventHandlers(
        for recognizer: SPXTranslationRecognizer,
        inputLanguage: InputLanguage,
        processingGeneration: Int
    ) {
        let interimGate = SpeechInterimUpdateGate(updateInterval: Self.interimUpdateInterval)

        configureRecognizingEventHandler(for: recognizer, interimGate: interimGate)
        configureRecognizedEventHandler(
            for: recognizer,
            inputLanguage: inputLanguage,
            processingGeneration: processingGeneration
        )

        recognizer.addCanceledEventHandler { [weak self] _, event in
            let message = event.errorDetails?.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { [weak self] in
                let detail = message?.isEmpty == false
                    ? message!
                    : L10n.text("speechRecognition.cancelled")
                self?.captionPreviewState.setFailure(
                    detail
                )
                self?.onLogEvent?(
                    PortalWorkflowLog(
                        level: .error,
                        title: L10n.text("log.speech.recognitionCanceled"),
                        detail: detail
                    )
                )
            }
        }
    }

    private func configureRecognizingEventHandler(
        for recognizer: SPXTranslationRecognizer,
        interimGate: SpeechInterimUpdateGate
    ) {
        recognizer.addRecognizingEventHandler { [weak self] _, event in
            guard let text = event.result.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty,
                  interimGate.shouldPublish(text)
            else {
                return
            }

            let translations = Self.normalizedTranslations(from: event.result.translations)
            DispatchQueue.main.async { [weak self] in
                self?.captionPreviewState.setRecognizingTranscript(
                    text,
                    translations: translations,
                    offsetTicks: event.result.offset
                )
            }
        }
    }

    private func configureRecognizedEventHandler(
        for recognizer: SPXTranslationRecognizer,
        inputLanguage: InputLanguage,
        processingGeneration: Int
    ) {
        recognizer.addRecognizedEventHandler { [weak self] _, event in
            guard let captionEvent = Self.captionEvent(
                from: event.result,
                inputLanguage: inputLanguage,
                processingGeneration: processingGeneration
            ) else {
                return
            }

            let translations = Self.normalizedTranslations(from: event.result.translations)
            DispatchQueue.main.async { [weak self] in
                self?.captionPreviewState.setFinalTranscript(
                    captionEvent.text,
                    translations: translations,
                    offsetTicks: event.result.offset
                )
                self?.deferCaptionEvent(captionEvent, processingGeneration: processingGeneration)
            }
        }
    }

    private static func normalizedTranslations(from translations: [AnyHashable: Any]) -> [String: String] {
        var normalizedTranslations: [String: String] = [:]

        for (language, value) in translations {
            guard let language = language as? String,
                  let text = value as? String
            else {
                continue
            }

            let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedText.isEmpty {
                normalizedTranslations[language] = normalizedText
            }
        }

        return normalizedTranslations
    }

    private static func captionEvent(
        from result: SPXTranslationRecognitionResult,
        inputLanguage: InputLanguage,
        processingGeneration: Int
    ) -> RecognizedCaptionEvent? {
        guard result.reason == .translatedSpeech,
              let text = result.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return nil
        }

        return RecognizedCaptionEvent(
            text: text,
            translations: normalizedTranslations(from: result.translations),
            offsetTicks: result.offset,
            durationTicks: result.duration,
            inputLanguage: inputLanguage,
            processingGeneration: processingGeneration
        )
    }

    private func deferCaptionEvent(_ event: RecognizedCaptionEvent, processingGeneration: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in

            guard let self else {
                return
            }

            guard activeRequest?.processingGeneration == processingGeneration else {
                return
            }

            recognizedCaptionCount += 1
            onCaptionCountChanged?(recognizedCaptionCount)
            onCaptionEvent?(event)
        }
    }
}
