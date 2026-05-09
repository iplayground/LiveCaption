import Foundation
import Combine
import SwiftUI

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

    func clearLivePreviewAfterInputLanguageChange() {
        updateSnapshot { snapshot in
            snapshot.interimTranscript = ""
            snapshot.visibleLiveTranscript = ""
            snapshot.interimTranslations = [:]
            snapshot.finalTranscript = ""
            snapshot.finalTranslations = [:]
            snapshot.finalTranscriptHistory = []
            snapshot.finalTranslationHistory = [:]
            snapshot.lastFinalOffsetTicks = nil
            snapshot.projectionOverrideText = ""
            snapshot.suppressesWelcomeText = true
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

    private static func trimRetainedHistory(_ target: inout [String], limit: Int) {
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
