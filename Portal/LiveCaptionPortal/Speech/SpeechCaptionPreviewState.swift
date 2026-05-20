import Foundation
import Combine
import SwiftUI

private struct TimedCaptionLine: Equatable {
    let offsetTicks: UInt64
    let text: String
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

    private var snapshot = SpeechCaptionPreviewSnapshot()

    var state: SpeechRecognitionState {
        snapshot.state
    }

    private var shouldShowWelcomeText: Bool {
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

    func projectionCaptionText(
        for language: SpeechOutputLanguage?,
        inputLanguage: InputLanguage,
        source: CaptionQualityMode = .fast,
        appendsText: Bool,
        appendLineLimit: Int
    ) -> String {
        if let projectionOverrideText = snapshot.projectionOverrideText {
            return projectionOverrideText
        }

        return computedProjectionCaptionText(
            for: language,
            inputLanguage: inputLanguage,
            source: source,
            appendsText: appendsText,
            appendLineLimit: appendLineLimit
        )
    }

    func clearProjectionCaption() {
        updateSnapshot { snapshot in
            snapshot.finalTranscriptHistory = []
            snapshot.finalTranslationHistory = [:]
            snapshot.accurateFinalTranscriptHistory = []
            snapshot.accurateFinalTranslationHistory = [:]
            snapshot.accurateFinalCaptionHistoryByLanguageID = [:]
            snapshot.projectionOverrideText = ""
        }
    }

    func fillProjectionCaption() {
        updateSnapshot { snapshot in
            Self.appendIfNeeded(snapshot.finalTranscript, to: &snapshot.finalTranscriptHistory)

            snapshot.finalTranslations.forEach { languageID, translation in
                Self.appendIfNeeded(translation, to: &snapshot.finalTranslationHistory[languageID, default: []])
            }

            Self.insertTimedCaptionIfNeeded(
                snapshot.accurateFinalTranscript,
                offsetTicks: snapshot.lastAccurateFinalOffsetTicks ?? 0,
                into: &snapshot.accurateFinalTranscriptHistory
            )
            snapshot.accurateFinalCaptionsByLanguageID.forEach { languageID, caption in
                Self.insertTimedCaptionIfNeeded(
                    caption,
                    offsetTicks: snapshot.lastAccurateFinalOffsetTicks ?? 0,
                    into: &snapshot.accurateFinalCaptionHistoryByLanguageID[languageID, default: []]
                )
            }

            snapshot.accurateFinalTranslations.forEach { languageID, translation in
                Self.insertTimedCaptionIfNeeded(
                    translation,
                    offsetTicks: snapshot.lastAccurateFinalOffsetTicks ?? 0,
                    into: &snapshot.accurateFinalTranslationHistory[languageID, default: []]
                )
            }

            snapshot.projectionOverrideText = nil
        }
    }

    func clearLivePreviewAfterInputLanguageChange() {
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
            snapshot.projectionOverrideText = ""
            snapshot.suppressesWelcomeText = true
        }
    }

    private func computedProjectionCaptionText(
        for language: SpeechOutputLanguage?,
        inputLanguage: InputLanguage,
        source: CaptionQualityMode,
        appendsText: Bool,
        appendLineLimit: Int
    ) -> String {
        if source == .accurate {
            return computedAccurateProjectionCaptionText(
                for: language,
                inputLanguage: inputLanguage,
                appendsText: appendsText,
                appendLineLimit: appendLineLimit
            )
        }

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

    private func computedAccurateProjectionCaptionText(
        for language: SpeechOutputLanguage?,
        inputLanguage: InputLanguage,
        appendsText: Bool,
        appendLineLimit: Int
    ) -> String {
        guard appendsText else {
            guard let language else {
                return accurateFinalTranscriptText(for: inputLanguage)
            }

            return accurateFinalCaptionText(for: language, inputLanguage: inputLanguage)
        }

        guard let language else {
            let sourceLanguageID = inputLanguage.matchingOutputLanguageID
            if let lines = snapshot.accurateFinalCaptionHistoryByLanguageID[sourceLanguageID], !lines.isEmpty {
                return recentProjectionText(
                    from: lines.map(\.text),
                    previewText: inputLanguage.previewText,
                    lineLimit: appendLineLimit
                )
            }

            return recentProjectionText(
                from: snapshot.accurateFinalTranscriptHistory.map(\.text),
                previewText: inputLanguage.previewText,
                lineLimit: appendLineLimit
            )
        }

        if language.id == inputLanguage.matchingOutputLanguageID {
            return recentProjectionText(
                from: snapshot.accurateFinalCaptionHistoryByLanguageID[language.id, default: []].map(\.text),
                previewText: inputLanguage.previewText,
                lineLimit: appendLineLimit
            )
        }

        let lines = snapshot.accurateFinalCaptionHistoryByLanguageID[language.id, default: []]
        return recentProjectionText(
            from: lines.map(\.text),
            previewText: language.previewText,
            lineLimit: appendLineLimit
        )
    }

    private func accurateFinalTranscriptText(for inputLanguage: InputLanguage) -> String {
        if !snapshot.accurateFinalTranscript.isEmpty {
            return snapshot.accurateFinalTranscript
        }

        return shouldShowWelcomeText ? inputLanguage.previewText : ""
    }

    private func accurateFinalCaptionText(for language: SpeechOutputLanguage, inputLanguage: InputLanguage) -> String {
        if let text = snapshot.accurateFinalCaptionsByLanguageID[language.id], !text.isEmpty {
            return text
        }

        if language.id == inputLanguage.matchingOutputLanguageID {
            return accurateFinalTranscriptText(for: inputLanguage)
        }

        if let text = snapshot.accurateFinalTranslations[language.id], !text.isEmpty {
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
            let shouldUpdateLatest: Bool
            if let lastGeneration = snapshot.lastAccurateFinalProcessingGeneration {
                shouldUpdateLatest = processingGeneration > lastGeneration
                    || (
                        processingGeneration == lastGeneration
                            && offsetTicks > (snapshot.lastAccurateFinalOffsetTicks ?? 0)
                    )
            } else {
                shouldUpdateLatest = true
            }

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

    private static func appendIfNeeded(_ text: String, to target: inout [String]) {
        guard !text.isEmpty, target.last != text else {
            return
        }

        target.append(text)
        trimRetainedHistory(&target, limit: retainedHistoryLimit())
    }

    private static func insertTimedCaptionIfNeeded(
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
