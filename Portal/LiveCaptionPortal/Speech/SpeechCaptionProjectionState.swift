import Foundation

extension SpeechCaptionPreviewState {
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

    func computedProjectionCaptionText(
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

    func computedAccurateProjectionCaptionText(
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

    func accurateFinalTranscriptText(for inputLanguage: InputLanguage) -> String {
        if !snapshot.accurateFinalTranscript.isEmpty {
            return snapshot.accurateFinalTranscript
        }

        return shouldShowWelcomeText ? inputLanguage.previewText : ""
    }

    func accurateFinalCaptionText(for language: SpeechOutputLanguage, inputLanguage: InputLanguage) -> String {
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

    func appendedTranscriptText(for inputLanguage: InputLanguage, lineLimit: Int) -> String {
        var lines = snapshot.finalTranscriptHistory

        if case .recognizing = snapshot.state,
           !snapshot.visibleLiveTranscript.isEmpty,
           lines.last != snapshot.visibleLiveTranscript {
            lines.append(snapshot.visibleLiveTranscript)
        }

        return recentProjectionText(from: lines, previewText: inputLanguage.previewText, lineLimit: lineLimit)
    }

    func recentProjectionText(from lines: [String], previewText: String, lineLimit: Int) -> String {
        let visibleLines = lines.filter { !$0.isEmpty }

        if visibleLines.isEmpty {
            return shouldShowWelcomeText ? previewText : ""
        }

        return visibleLines
            .suffix(max(1, lineLimit))
            .joined(separator: "\n")
    }
}
