import SwiftUI
import Combine
import MicrosoftCognitiveServicesSpeech

struct SpeechConnectionTestResult {
    let region: String
}

enum SpeechRecognitionState: Equatable {
    case idle
    case listening
    case recognizing
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            L10n.text("speechRecognition.state.idle")
        case .listening:
            L10n.text("speechRecognition.state.listening")
        case .recognizing:
            L10n.text("speechRecognition.state.recognizing")
        case .failed:
            L10n.text("speechRecognition.state.failed")
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "pause.circle"
        case .listening:
            "ear"
        case .recognizing:
            "waveform.badge.magnifyingglass"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            .secondary
        case .listening:
            .blue
        case .recognizing:
            .green
        case .failed:
            .red
        }
    }
}

@MainActor
final class SpeechRecognitionController: ObservableObject {
    let captionPreviewState = SpeechCaptionPreviewState()
    var onCaptionEvent: ((RecognizedCaptionEvent) -> Void)?
    var onCaptionCountChanged: ((Int) -> Void)?

    private static let interimUpdateInterval: TimeInterval = 1.0 / 12.0
    private static let phraseListWeight = 2.0
    private var recognizer: SPXTranslationRecognizer?
    private var activeRequest: SpeechRecognitionRequest?
    private var recognizedCaptionCount = 0

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
        let region = settings.region.trimmingCharacters(in: .whitespacesAndNewlines)
        let speechKey = settings.speechKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard authorizationStatus == .authorized else {
            stopRecognition(resetTranscript: false)
            captionPreviewState.setFailure(L10n.text("speechRecognition.error.notAuthorized"))
            return
        }

        guard !region.isEmpty, !speechKey.isEmpty else {
            stopRecognition(resetTranscript: false)
            captionPreviewState.setFailure(L10n.text("speechRecognition.error.missingRegionOrKey"))
            return
        }

        guard let audioDeviceID, !audioDeviceID.isEmpty else {
            stopRecognition(resetTranscript: false)
            captionPreviewState.setFailure(L10n.text("speechRecognition.error.noAudioSourceSelected"))
            return
        }

        let outputLanguageIDs = settings.selectedOutputLanguages
            .map(\.id)
            .sorted()
        let phraseHints = settings.phraseHints(for: inputLanguage)

        let request = SpeechRecognitionRequest(
            region: region,
            speechKey: speechKey,
            inputLocale: inputLanguage.speechLocale,
            audioDeviceID: audioDeviceID,
            outputLanguageIDs: outputLanguageIDs,
            phraseHints: phraseHints,
            sentenceSilenceTimeoutMilliseconds: settings.sentenceSilenceTimeoutMilliseconds,
            processingGeneration: processingGeneration
        )

        guard request != activeRequest || recognizer == nil else {
            return
        }

        stopRecognition(resetTranscript: false)
        activeRequest = request

        do {
            let translationConfiguration = try SPXSpeechTranslationConfiguration(
                subscription: speechKey,
                region: region
            )

            translationConfiguration.speechRecognitionLanguage = inputLanguage.speechLocale
            translationConfiguration.setPropertyTo("Time", by: SPXPropertyId(rawValue: 9_004)!)
            translationConfiguration.setPropertyTo(
                "\(settings.sentenceSilenceTimeoutMilliseconds)",
                by: SPXPropertyId(rawValue: 9_002)!
            )
            outputLanguageIDs
                .filter { $0 != inputLanguage.matchingOutputLanguageID }
                .forEach { translationConfiguration.addTargetLanguage($0) }

            guard let audioConfiguration = SPXAudioConfiguration(microphone: audioDeviceID) else {
                throw SpeechRecognitionError.audioConfigurationFailed
            }

            let translationRecognizer = try SPXTranslationRecognizer(
                speechTranslationConfiguration: translationConfiguration,
                audioConfiguration: audioConfiguration
            )

            applyPhraseHints(phraseHints, to: translationRecognizer)
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

        recognizer.addRecognizedEventHandler { [weak self] _, event in
            let result = event.result
            guard result.reason == .translatedSpeech,
                  let text = result.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else {
                return
            }

            let translations = Self.normalizedTranslations(from: result.translations)
            let captionEvent = RecognizedCaptionEvent(
                text: text,
                translations: translations,
                offsetTicks: result.offset,
                durationTicks: result.duration,
                inputLanguage: inputLanguage,
                processingGeneration: processingGeneration
            )

            DispatchQueue.main.async { [weak self] in
                self?.captionPreviewState.setFinalTranscript(
                    text,
                    translations: translations,
                    offsetTicks: result.offset
                )

                self?.deferCaptionEvent(captionEvent, processingGeneration: processingGeneration)
            }
        }

        recognizer.addCanceledEventHandler { [weak self] _, event in
            let message = event.errorDetails?.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { [weak self] in
                self?.captionPreviewState.setFailure(message?.isEmpty == false ? message! : L10n.text("speechRecognition.cancelled"))
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

private final class SpeechInterimUpdateGate: @unchecked Sendable {
    private let updateInterval: TimeInterval
    private let lock = NSLock()
    private var lastUpdate = Date.distantPast
    private var lastText = ""

    init(updateInterval: TimeInterval) {
        self.updateInterval = updateInterval
    }

    func shouldPublish(_ text: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        guard text != lastText,
              now.timeIntervalSince(lastUpdate) >= updateInterval else {
            return false
        }

        lastText = text
        lastUpdate = now
        return true
    }
}

enum SpeechRecognitionError: LocalizedError {
    case audioConfigurationFailed

    var errorDescription: String? {
        switch self {
        case .audioConfigurationFailed:
            L10n.text("speechRecognition.error.audioConfigurationFailed")
        }
    }
}
