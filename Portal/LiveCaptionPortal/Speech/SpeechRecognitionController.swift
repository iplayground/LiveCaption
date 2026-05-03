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

private struct SpeechCaptionPreviewSnapshot {
    var state = SpeechRecognitionState.idle
    var interimTranscript = ""
    var visibleLiveTranscript = ""
    var interimTranslations: [String: String] = [:]
    var finalTranscript = ""
    var finalTranslations: [String: String] = [:]
    var finalTranscriptHistory: [String] = []
    var finalTranslationHistory: [String: [String]] = [:]
    var lastFinalOffsetTicks: UInt64?
    var projectionOverrideText: String?
}

struct SpeechRecognitionRequest: Equatable {
    let region: String
    let speechKey: String
    let inputLocale: String
    let audioDeviceID: String
    let outputLanguageIDs: [String]
    let phraseHints: [String]
    let sentenceSilenceTimeoutMilliseconds: Int
}

@MainActor
final class SpeechCaptionPreviewState: ObservableObject {
    @Published private var snapshot = SpeechCaptionPreviewSnapshot()

    var state: SpeechRecognitionState {
        snapshot.state
    }

    private var shouldShowWelcomeText: Bool {
        if case .idle = snapshot.state {
            return true
        }

        return false
    }

    func liveTranscript(for inputLanguage: InputLanguage) -> String {
        if !snapshot.visibleLiveTranscript.isEmpty {
            return snapshot.visibleLiveTranscript
        }

        return shouldShowWelcomeText ? inputLanguage.previewText : ""
    }

    func displayTranscript(for inputLanguage: InputLanguage) -> String {
        if !snapshot.interimTranscript.isEmpty {
            return snapshot.interimTranscript
        }

        if !snapshot.finalTranscript.isEmpty {
            return snapshot.finalTranscript
        }

        return shouldShowWelcomeText ? inputLanguage.previewText : ""
    }

    func captionText(for language: SpeechOutputLanguage, inputLanguage: InputLanguage) -> String {
        if language.id == inputLanguage.matchingOutputLanguageID {
            return displayTranscript(for: inputLanguage)
        }

        if let text = snapshot.interimTranslations[language.id], !text.isEmpty {
            return text
        }

        if let text = snapshot.finalTranslations[language.id], !text.isEmpty {
            return text
        }

        return shouldShowWelcomeText ? language.previewText : ""
    }

    func finalCaptionText(for language: SpeechOutputLanguage, inputLanguage: InputLanguage) -> String {
        if language.id == inputLanguage.matchingOutputLanguageID {
            if !snapshot.finalTranscript.isEmpty {
                return snapshot.finalTranscript
            }

            return shouldShowWelcomeText ? inputLanguage.previewText : ""
        }

        if let text = snapshot.finalTranslations[language.id], !text.isEmpty {
            return text
        }

        return shouldShowWelcomeText ? language.previewText : ""
    }

    func projectionCaptionText(
        for language: SpeechOutputLanguage?,
        inputLanguage: InputLanguage,
        appendsText: Bool,
        appendLineLimit: Int
    ) -> String {
        if let projectionOverrideText = snapshot.projectionOverrideText {
            return projectionOverrideText
        }

        return computedProjectionCaptionText(
            for: language,
            inputLanguage: inputLanguage,
            appendsText: appendsText,
            appendLineLimit: appendLineLimit
        )
    }

    func clearProjectionCaption() {
        updateSnapshot { snapshot in
            snapshot.finalTranscriptHistory = []
            snapshot.finalTranslationHistory = [:]
            snapshot.projectionOverrideText = ""
        }
    }

    func fillProjectionCaption() {
        updateSnapshot { snapshot in
            Self.appendIfNeeded(snapshot.finalTranscript, to: &snapshot.finalTranscriptHistory)

            snapshot.finalTranslations.forEach { languageID, translation in
                Self.appendIfNeeded(translation, to: &snapshot.finalTranslationHistory[languageID, default: []])
            }

            snapshot.projectionOverrideText = nil
        }
    }

    private func computedProjectionCaptionText(
        for language: SpeechOutputLanguage?,
        inputLanguage: InputLanguage,
        appendsText: Bool,
        appendLineLimit: Int
    ) -> String {
        guard appendsText else {
            guard let language else {
                return displayTranscript(for: inputLanguage)
            }

            if language.id != inputLanguage.matchingOutputLanguageID {
                return finalCaptionText(for: language, inputLanguage: inputLanguage)
            }

            return captionText(for: language, inputLanguage: inputLanguage)
        }

        guard let language else {
            return appendedTranscriptText(for: inputLanguage, lineLimit: appendLineLimit)
        }

        if language.id == inputLanguage.matchingOutputLanguageID {
            return appendedTranscriptText(for: inputLanguage, lineLimit: appendLineLimit)
        }

        let lines = snapshot.finalTranslationHistory[language.id, default: []]
        return recentProjectionText(from: lines, previewText: language.previewText, lineLimit: appendLineLimit)
    }

    func setListening() {
        updateSnapshot { snapshot in
            snapshot.state = .listening
        }
    }

    func setIdle() {
        updateSnapshot { snapshot in
            snapshot.state = .idle
        }
    }

    func setRecognizingTranscript(_ text: String, translations: [String: String], offsetTicks: UInt64) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return
        }

        updateSnapshot { snapshot in
            if let lastFinalOffsetTicks = snapshot.lastFinalOffsetTicks,
               offsetTicks <= lastFinalOffsetTicks {
                return
            }

            snapshot.interimTranscript = normalizedText
            snapshot.visibleLiveTranscript = normalizedText
            Self.mergeNonEmptyTranslations(translations, into: &snapshot.interimTranslations)
            snapshot.projectionOverrideText = nil

            if case .recognizing = snapshot.state {
                return
            }

            snapshot.state = .recognizing
        }
    }

    func setFinalTranscript(_ text: String, translations: [String: String], offsetTicks: UInt64) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return
        }

        updateSnapshot { snapshot in
            snapshot.interimTranscript = ""
            snapshot.visibleLiveTranscript = normalizedText
            snapshot.finalTranscript = normalizedText
            Self.mergeNonEmptyTranslations(translations, into: &snapshot.finalTranslations)
            snapshot.finalTranscriptHistory.append(normalizedText)
            snapshot.lastFinalOffsetTicks = offsetTicks
            snapshot.projectionOverrideText = nil

            translations.forEach { languageID, translation in
                guard !translation.isEmpty else {
                    return
                }

                snapshot.interimTranslations.removeValue(forKey: languageID)
                snapshot.finalTranslationHistory[languageID, default: []].append(translation)
            }
            snapshot.state = .listening
        }
    }

    func setFailure(_ message: String) {
        updateSnapshot { snapshot in
            snapshot.state = .failed(message)
        }
    }

    func resetTranscript() {
        updateSnapshot { snapshot in
            snapshot.interimTranscript = ""
            snapshot.visibleLiveTranscript = ""
            snapshot.interimTranslations = [:]
            snapshot.finalTranscript = ""
            snapshot.finalTranslations = [:]
            snapshot.finalTranscriptHistory = []
            snapshot.finalTranslationHistory = [:]
            snapshot.lastFinalOffsetTicks = nil
            snapshot.projectionOverrideText = nil
        }
    }

    private func appendedTranscriptText(for inputLanguage: InputLanguage, lineLimit: Int) -> String {
        var lines = snapshot.finalTranscriptHistory

        if case .recognizing = snapshot.state,
           !snapshot.visibleLiveTranscript.isEmpty,
           lines.last != snapshot.visibleLiveTranscript {
            lines.append(snapshot.visibleLiveTranscript)
        }

        return recentProjectionText(from: lines, previewText: inputLanguage.previewText, lineLimit: lineLimit)
    }

    private func recentProjectionText(from lines: [String], previewText: String, lineLimit: Int) -> String {
        let visibleLines = lines.filter { !$0.isEmpty }

        if visibleLines.isEmpty {
            return shouldShowWelcomeText ? previewText : ""
        }

        return visibleLines
            .suffix(max(1, lineLimit))
            .joined(separator: "\n")
    }

    private func updateSnapshot(_ update: (inout SpeechCaptionPreviewSnapshot) -> Void) {
        var nextSnapshot = snapshot
        update(&nextSnapshot)
        snapshot = nextSnapshot
    }

    private static func mergeNonEmptyTranslations(
        _ translations: [String: String],
        into target: inout [String: String]
    ) {
        translations.forEach { languageID, translation in
            guard !translation.isEmpty else {
                return
            }

            target[languageID] = translation
        }
    }

    private static func appendIfNeeded(_ text: String, to target: inout [String]) {
        guard !text.isEmpty, target.last != text else {
            return
        }

        target.append(text)
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
        authorizationStatus: SpeechAuthorizationStatus
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
            sentenceSilenceTimeoutMilliseconds: settings.sentenceSilenceTimeoutMilliseconds
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
            configureEventHandlers(for: translationRecognizer)

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

    private func configureEventHandlers(for recognizer: SPXTranslationRecognizer) {
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
                durationTicks: result.duration
            )

            DispatchQueue.main.async { [weak self] in
                self?.captionPreviewState.setFinalTranscript(
                    text,
                    translations: translations,
                    offsetTicks: result.offset
                )

                self?.deferCaptionEvent(captionEvent)
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

    private func deferCaptionEvent(_ event: RecognizedCaptionEvent) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in

            guard let self else {
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
