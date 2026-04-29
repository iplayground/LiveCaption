import SwiftUI
import Combine
import MicrosoftCognitiveServicesSpeech

struct SpeechConnectionTestResult {
    let region: String
}

enum SpeechRecognitionState {
    case idle
    case listening
    case recognizing
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            "等待語音"
        case .listening:
            "聆聽中"
        case .recognizing:
            "辨識中"
        case .failed:
            "辨識失敗"
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

struct SpeechRecognitionRequest: Equatable {
    let region: String
    let speechKey: String
    let inputLocale: String
    let audioDeviceID: String
    let outputLanguageIDs: [String]
}

@MainActor
final class SpeechRecognitionController: ObservableObject {
    @Published private(set) var state = SpeechRecognitionState.idle
    @Published private(set) var interimTranscript = ""
    @Published private(set) var finalTranscript = ""
    @Published private(set) var finalTranslations: [String: String] = [:]
    @Published private(set) var recognizedCaptionCount = 0
    @Published private(set) var latestCaptionEvent: RecognizedCaptionEvent?

    private var recognizer: SPXTranslationRecognizer?
    private var activeRequest: SpeechRecognitionRequest?

    private var shouldShowWelcomeText: Bool {
        if case .idle = state {
            return true
        }

        return false
    }

    func displayTranscript(for inputLanguage: InputLanguage) -> String {
        if !interimTranscript.isEmpty {
            return interimTranscript
        }

        if !finalTranscript.isEmpty {
            return finalTranscript
        }

        return shouldShowWelcomeText ? inputLanguage.previewText : ""
    }

    func captionText(for language: SpeechOutputLanguage, inputLanguage: InputLanguage) -> String {
        if language.id == inputLanguage.matchingOutputLanguageID {
            return displayTranscript(for: inputLanguage)
        }

        if let text = finalTranslations[language.id], !text.isEmpty {
            return text
        }

        return shouldShowWelcomeText ? language.previewText : ""
    }

    func startRecognition(
        settings: SpeechSettings,
        inputLanguage: InputLanguage,
        audioDeviceID: String?,
        authorizationStatus: SpeechAuthorizationStatus
    ) {
        let region = settings.region.trimmingCharacters(in: .whitespacesAndNewlines)
        let speechKey = settings.speechKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard authorizationStatus == .authorized else {
            stopRecognition(resetTranscript: false)
            state = .failed("Speech 尚未授權")
            return
        }

        guard !region.isEmpty, !speechKey.isEmpty else {
            stopRecognition(resetTranscript: false)
            state = .failed("缺少 Speech Region 或 Key")
            return
        }

        guard let audioDeviceID, !audioDeviceID.isEmpty else {
            stopRecognition(resetTranscript: false)
            state = .failed("尚未選擇音訊來源")
            return
        }

        let outputLanguageIDs = settings.selectedOutputLanguages
            .map(\.id)
            .sorted()

        let request = SpeechRecognitionRequest(
            region: region,
            speechKey: speechKey,
            inputLocale: inputLanguage.speechLocale,
            audioDeviceID: audioDeviceID,
            outputLanguageIDs: outputLanguageIDs
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

            configureEventHandlers(for: translationRecognizer)

            try translationRecognizer.startContinuousRecognition()

            recognizer = translationRecognizer
            state = .listening
        } catch {
            activeRequest = nil
            recognizer = nil
            state = .failed(error.localizedDescription)
        }
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
        state = .idle

        if resetTranscript {
            interimTranscript = ""
            finalTranscript = ""
            finalTranslations = [:]
            recognizedCaptionCount = 0
        }
    }

    private func configureEventHandlers(for recognizer: SPXTranslationRecognizer) {
        recognizer.addRecognizingEventHandler { [weak self] _, event in
            guard let text = event.result.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else {
                return
            }

            Task { @MainActor [weak self] in
                self?.interimTranscript = text
                self?.state = .recognizing
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

            Task { @MainActor [weak self] in
                self?.interimTranscript = ""
                self?.finalTranscript = text
                let translations = Self.normalizedTranslations(from: result.translations)
                self?.finalTranslations = translations
                self?.recognizedCaptionCount += 1
                self?.latestCaptionEvent = RecognizedCaptionEvent(
                    text: text,
                    translations: translations,
                    offsetTicks: result.offset,
                    durationTicks: result.duration
                )
                self?.state = .listening
            }
        }

        recognizer.addCanceledEventHandler { [weak self] _, event in
            let message = event.errorDetails?.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor [weak self] in
                self?.state = .failed(message?.isEmpty == false ? message! : "Speech Translation 已取消")
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
}

enum SpeechRecognitionError: LocalizedError {
    case audioConfigurationFailed

    var errorDescription: String? {
        switch self {
        case .audioConfigurationFailed:
            "無法建立音訊輸入設定"
        }
    }
}
