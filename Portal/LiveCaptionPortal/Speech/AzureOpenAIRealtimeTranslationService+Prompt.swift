import Foundation

extension AzureOpenAIRealtimeTranslationService {
    static func systemPrompt(
        inputLanguage: InputLanguage,
        phraseHints: [String],
        targetLanguages: [SpeechOutputLanguage]
    ) -> String {
        let languageList = targetLanguages
            .map { "\($0.id): \($0.azureOpenAITextTranslationName)" }
            .joined(separator: "\n")
        let normalizedPhraseHints = phraseHints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let phraseHintText = normalizedPhraseHints.isEmpty
            ? "None"
            : normalizedPhraseHints.joined(separator: ", ")

        return """
        \(sourceTextGuidance(inputLanguage: inputLanguage))
        Return only a JSON object with this shape:
        {
          "sourceText": "corrected source-language subtitle",
          "translations": {
            "language-id": "translated subtitle"
          }
        }
        The translations object must use only the exact language IDs listed below.
        Keep translations concise and suitable for event subtitles.
        For zh-Hant, use Taiwan Traditional Chinese and Taiwan terminology. Never output Simplified Chinese.

        Vocabulary hints:
        \(phraseHintText)

        Languages:
        \(languageList)
        """
    }

    static func sourceTextGuidance(inputLanguage: InputLanguage) -> String {
        """
        Produce one faithful source-language subtitle in \(inputLanguage.azureOpenAITextNormalizationName)
        as sourceText,
        then translate sourceText into the requested languages.
        Choose sourceText from transcriptCandidates. Prefer the Azure OpenAI candidate when it is present and coherent.
        Use the Azure Speech candidate only as secondary evidence. Ignore Azure Speech when it is clearly garbled,
        phonetically mistranscribed, or conflicts with stable previousSourceTexts.
        Use Azure Speech as the fallback source only when the Azure OpenAI candidate is missing, empty,
        or clearly damaged.
        Use previousSourceTexts and vocabulary hints only as conservative source-language context for homophones,
        near-sound words, segmentation, code-switching, topic continuity, spelling, capitalization, punctuation,
        and Traditional Chinese normalization.
        Treat previousSourceTexts as source-language context, not translated evidence. Preserve the current talk topic
        across adjacent subtitles when resolving ambiguous candidates.
        Preserve the heard language form in sourceText when it is supported by the candidates or previousSourceTexts.
        Do not replace code-switched text with phonetically similar words in another language.
        If a candidate phrase is unnatural in the source language and a homophone or near-sound alternative is supported
        by context, use the natural source-language alternative.
        If a code-switch phrase is unnatural in the surrounding source-language context, and a near-sound code-switch
        phrase is supported by context, use the contextual phrase.
        For Mandarin sourceText, be especially careful when speech includes English code-switching. Do not normalize
        an ambiguous candidate into a meaning that changes the current topic unless the current candidates clearly
        support that topic shift.
        Do not add content the speaker did not say, copy from previousSourceTexts, beautify wording,
        formalize spoken language, paraphrase, summarize, expand, or censor.
        If uncertain, keep the most reliable candidate wording.
        """
    }

    static func userContent(
        transcriptDrafts: [AccurateCaptionTranscriptDraft],
        previousSourceTexts: [String]
    ) throws -> String {
        let candidates = transcriptDrafts.map { draft in
            [
                "provider": draft.providerID,
                "text": draft.normalizedText,
            ]
        }
        let payload: [String: Any] = [
            "previousSourceTexts": normalizedPreviousSourceTexts(previousSourceTexts),
            "transcriptCandidates": candidates,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let content = String(bytes: data, encoding: .utf8) else {
            throw AzureOpenAITextTranslationError.invalidResponse(detail: "reason=invalidUserContentEncoding")
        }
        return content
    }

    static func normalizedPreviousSourceTexts(_ sourceTexts: [String]) -> [String] {
        Array(
            sourceTexts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .suffix(maximumPreviousSourceTextCount)
        )
    }

    func appendRecentSourceText(_ sourceText: String) {
        let normalizedSourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSourceText.isEmpty else {
            return
        }

        recentSourceTexts.append(normalizedSourceText)
        if recentSourceTexts.count > Self.maximumPreviousSourceTextCount {
            recentSourceTexts.removeFirst(recentSourceTexts.count - Self.maximumPreviousSourceTextCount)
        }
    }

    static func responseErrorDetail(from data: Data) -> String {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = payload["error"] as? [String: Any]
        else {
            return "missing"
        }

        let message = error["message"] as? String ?? "missing"
        let type = error["type"] as? String ?? "missing"
        let code = error["code"] as? String ?? "missing"
        return "serverError=\(message); type=\(type); code=\(code)"
    }

    func emitDiagnostic(level: AzureOpenAIRealtimeTranslationDiagnostic.Level, detail: String) {
        onDiagnostic?(AzureOpenAIRealtimeTranslationDiagnostic(level: level, detail: detail))
    }

    static func translationMissingLanguagesDetail(
        targetLanguages: [String],
        returnedLanguages: [String],
        missingLanguages: [String]
    ) -> String {
        [
            "phase=translationCompleted",
            "issue=missingLanguages",
            "targetLanguages=\(targetLanguages.sorted().joined(separator: ","))",
            "returnedLanguages=\(returnedLanguages.sorted().joined(separator: ","))",
            "missingLanguages=\(missingLanguages.sorted().joined(separator: ","))",
        ].joined(separator: "; ")
    }

    static func invalidResponseDetail(payload: [String: Any], contentChars: Int?) -> String {
        let choices = payload["choices"] as? [[String: Any]]
        let firstChoice = choices?.first
        let finishReason = firstChoice?["finish_reason"] as? String ?? "missing"
        var parts = [
            "reason=invalidResponse",
            "choices=\(choices?.count ?? 0)",
            "finishReason=\(finishReason)",
        ]
        if let contentChars {
            parts.append("contentChars=\(contentChars)")
        }
        return parts.joined(separator: "; ")
    }

    static func errorDetail(_ error: Error, phase: String) -> String {
        switch error {
        case let error as AzureOpenAITextTranslationError:
            "phase=\(phase); \(error.diagnosticDescription)"
        default:
            "phase=\(phase); error=\(error.localizedDescription)"
        }
    }

    static func retryAfterSeconds(from response: HTTPURLResponse) -> Double? {
        let retryAfterValue = response.value(forHTTPHeaderField: "retry-after")
            ?? response.value(forHTTPHeaderField: "Retry-After")
        guard let retryAfterValue else {
            return nil
        }

        if let seconds = Double(retryAfterValue) {
            return seconds
        }

        if let retryDate = HTTPDateFormatter.date(from: retryAfterValue) {
            return max(retryDate.timeIntervalSinceNow, 0)
        }

        return nil
    }

    static func retryDelayNanoseconds(for error: Error, attempt: Int) -> UInt64? {
        guard case let AzureOpenAITextTranslationError.httpError(statusCode, _, retryAfterSeconds) = error,
              statusCode == 429
        else {
            return nil
        }

        let fallbackDelaySeconds = min(pow(2.0, Double(attempt)), 8.0)
        let delaySeconds = retryAfterSeconds ?? fallbackDelaySeconds
        return UInt64(max(delaySeconds, 1.0) * 1_000_000_000)
    }
}

struct AzureOpenAIRealtimeTranslationDiagnostic: Equatable, Sendable {
    enum Level: Equatable, Sendable {
        case warning
        case error
    }

    let level: Level
    let detail: String
}

enum AzureOpenAITextTranslationError: Error {
    case httpError(statusCode: Int, detail: String, retryAfterSeconds: Double?)
    case invalidResponse(detail: String)

    var diagnosticDescription: String {
        switch self {
        case .httpError(let statusCode, let detail, let retryAfterSeconds):
            if let retryAfterSeconds {
                "httpStatus=\(statusCode); retryAfterSeconds=\(String(format: "%.2f", retryAfterSeconds)); \(detail)"
            } else {
                "httpStatus=\(statusCode); \(detail)"
            }
        case .invalidResponse(let detail):
            detail
        }
    }
}

private enum HTTPDateFormatter {
    nonisolated static func date(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }
}

private extension SpeechOutputLanguage {
    nonisolated var azureOpenAITextTranslationName: String {
        switch id {
        case "zh-Hant":
            "Taiwan Traditional Chinese"
        case "en":
            "English"
        case "ja":
            "Japanese"
        case "ko":
            "Korean"
        default:
            id
        }
    }
}

private extension InputLanguage {
    nonisolated var azureOpenAITextNormalizationName: String {
        switch self {
        case .mandarin:
            "Mandarin Chinese"
        case .english:
            "English"
        }
    }
}
