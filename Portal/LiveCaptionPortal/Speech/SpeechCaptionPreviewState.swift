import Foundation
import Combine
import SwiftUI

struct TimedCaptionLine: Equatable {
    let offsetTicks: UInt64
    let text: String
}

struct SpeechCaptionPreviewSnapshot {
    var state = SpeechRecognitionState.idle
    var interimTranscript = ""
    var visibleLiveTranscript = ""
    var interimTranslations: [String: String] = [:]
    var finalTranscript = ""
    var finalTranslations: [String: String] = [:]
    var finalTranscriptHistory: [String] = []
    var finalTranslationHistory: [String: [String]] = [:]
    var accurateFinalTranscript = ""
    var accurateFinalTranslations: [String: String] = [:]
    var accurateFinalCaptionsByLanguageID: [String: String] = [:]
    var accurateFinalTranscriptHistory: [TimedCaptionLine] = []
    var accurateFinalTranslationHistory: [String: [TimedCaptionLine]] = [:]
    var accurateFinalCaptionHistoryByLanguageID: [String: [TimedCaptionLine]] = [:]
    var lastFinalOffsetTicks: UInt64?
    var lastAccurateFinalOffsetTicks: UInt64?
    var lastAccurateFinalProcessingGeneration: Int?
    var projectionOverrideText: String?
    var suppressesWelcomeText = false
}

struct SpeechRecognitionRequest: Equatable {
    let region: String
    let speechKey: String
    let inputLocale: String
    let audioDeviceID: String
    let outputLanguageIDs: [String]
    let phraseHints: [String]
    let sentenceSilenceTimeoutMilliseconds: Int
    let processingGeneration: Int
}

@MainActor
final class SpeechCaptionPreviewState: ObservableObject {
    private static let projectionAppendLineLimitKey = "projectionCapture.appendLineLimit"
    private static let defaultRetainedHistoryCount = 3
    private static let minimumRetainedHistoryCount = 1
    private static let maximumRetainedHistoryCount = 10

    var snapshot = SpeechCaptionPreviewSnapshot()
}

extension SpeechCaptionPreviewState {
    var state: SpeechRecognitionState {
        snapshot.state
    }

    var shouldShowWelcomeText: Bool {
        if case .idle = snapshot.state {
            return !snapshot.suppressesWelcomeText
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
            snapshot.suppressesWelcomeText = false

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
            Self.trimRetainedHistory(&snapshot.finalTranscriptHistory, limit: Self.retainedHistoryLimit())
            snapshot.lastFinalOffsetTicks = offsetTicks
            snapshot.projectionOverrideText = nil
            snapshot.suppressesWelcomeText = false

            translations.forEach { languageID, translation in
                guard !translation.isEmpty else {
                    return
                }

                snapshot.interimTranslations.removeValue(forKey: languageID)
                snapshot.finalTranslationHistory[languageID, default: []].append(translation)
                Self.trimRetainedHistory(
                    &snapshot.finalTranslationHistory[languageID, default: []],
                    limit: Self.retainedHistoryLimit()
                )
            }
            snapshot.state = .listening
        }
    }

    func setAccurateFinalCaption(
        _ text: String,
        translations: [String: String],
        offsetTicks: UInt64,
        inputLanguage: InputLanguage,
        processingGeneration: Int
    ) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return
        }

        updateSnapshot { snapshot in
            let shouldUpdateLatest = Self.shouldUpdateLatestAccurateFinalCaption(
                offsetTicks: offsetTicks,
                processingGeneration: processingGeneration,
                snapshot: snapshot
            )

            if shouldUpdateLatest {
                snapshot.accurateFinalTranscript = normalizedText
                Self.mergeNonEmptyTranslations(translations, into: &snapshot.accurateFinalTranslations)
                snapshot.lastAccurateFinalOffsetTicks = offsetTicks
                snapshot.lastAccurateFinalProcessingGeneration = processingGeneration
            }

            let sourceLanguageID = inputLanguage.matchingOutputLanguageID
            var captionsByLanguageID = translations
            captionsByLanguageID[sourceLanguageID] = normalizedText
            if shouldUpdateLatest {
                Self.mergeNonEmptyTranslations(captionsByLanguageID, into: &snapshot.accurateFinalCaptionsByLanguageID)
            }

            Self.insertTimedCaptionIfNeeded(
                normalizedText,
                offsetTicks: offsetTicks,
                into: &snapshot.accurateFinalTranscriptHistory
            )
            captionsByLanguageID.forEach { languageID, caption in
                Self.insertTimedCaptionIfNeeded(
                    caption,
                    offsetTicks: offsetTicks,
                    into: &snapshot.accurateFinalCaptionHistoryByLanguageID[languageID, default: []]
                )
            }
            snapshot.projectionOverrideText = nil
            snapshot.suppressesWelcomeText = false

            translations.forEach { languageID, translation in
                guard !translation.isEmpty else {
                    return
                }

                Self.insertTimedCaptionIfNeeded(
                    translation,
                    offsetTicks: offsetTicks,
                    into: &snapshot.accurateFinalTranslationHistory[languageID, default: []]
                )
            }
        }
    }

    private static func shouldUpdateLatestAccurateFinalCaption(
        offsetTicks: UInt64,
        processingGeneration: Int,
        snapshot: SpeechCaptionPreviewSnapshot
    ) -> Bool {
        guard let lastGeneration = snapshot.lastAccurateFinalProcessingGeneration else {
            return true
        }

        return processingGeneration > lastGeneration
            || (
                processingGeneration == lastGeneration
                    && offsetTicks > (snapshot.lastAccurateFinalOffsetTicks ?? 0)
            )
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
            snapshot.accurateFinalTranscript = ""
            snapshot.accurateFinalTranslations = [:]
            snapshot.accurateFinalCaptionsByLanguageID = [:]
            snapshot.accurateFinalTranscriptHistory = []
            snapshot.accurateFinalTranslationHistory = [:]
            snapshot.accurateFinalCaptionHistoryByLanguageID = [:]
            snapshot.lastFinalOffsetTicks = nil
            snapshot.lastAccurateFinalOffsetTicks = nil
            snapshot.lastAccurateFinalProcessingGeneration = nil
            snapshot.projectionOverrideText = nil
            snapshot.suppressesWelcomeText = false
        }
    }

    func updateSnapshot(_ update: (inout SpeechCaptionPreviewSnapshot) -> Void) {
        objectWillChange.send()
        update(&snapshot)
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

    static func appendIfNeeded(_ text: String, to target: inout [String]) {
        guard !text.isEmpty, target.last != text else {
            return
        }

        target.append(text)
        trimRetainedHistory(&target, limit: retainedHistoryLimit())
    }

    static func insertTimedCaptionIfNeeded(
        _ text: String,
        offsetTicks: UInt64,
        into target: inout [TimedCaptionLine]
    ) {
        guard !text.isEmpty,
              !target.contains(where: { $0.offsetTicks == offsetTicks && $0.text == text })
        else {
            return
        }

        let line = TimedCaptionLine(offsetTicks: offsetTicks, text: text)
        let insertionIndex = target.firstIndex { $0.offsetTicks > offsetTicks } ?? target.endIndex
        target.insert(line, at: insertionIndex)
        trimRetainedTimedHistory(&target, limit: retainedHistoryLimit())
    }

    private static func trimRetainedHistory(_ target: inout [String], limit: Int) {
        let overflowCount = target.count - limit
        guard overflowCount > 0 else {
            return
        }

        target.removeFirst(overflowCount)
    }

    private static func trimRetainedTimedHistory(_ target: inout [TimedCaptionLine], limit: Int) {
        let overflowCount = target.count - limit
        guard overflowCount > 0 else {
            return
        }

        target.removeFirst(overflowCount)
    }

    private static func retainedHistoryLimit() -> Int {
        let storedValue = UserDefaults.standard.double(forKey: projectionAppendLineLimitKey)
        let rawLimit = storedValue == 0 ? defaultRetainedHistoryCount : Int(storedValue.rounded())

        return min(
            max(rawLimit, minimumRetainedHistoryCount),
            maximumRetainedHistoryCount
        )
    }
}
