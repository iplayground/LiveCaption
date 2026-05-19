import Foundation

struct AzureOpenAIRealtimeTranslationConfiguration: Equatable, Sendable {
    let endpointURLString: String
    let translationDeploymentName: String
    let apiKey: String
    let targetLanguages: [SpeechOutputLanguage]

    nonisolated var isConfigured: Bool {
        !normalizedEndpointURLString.isEmpty
            && !translationDeploymentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated var normalizedEndpointURLString: String {
        var value = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}

struct AzureOpenAIRealtimeTranslationResult: Equatable, Sendable {
    let sourceText: String
    let translations: [String: String]
}

enum AzureOpenAIRealtimeTranslationError: LocalizedError {
    case incompleteConfiguration
    case invalidEndpoint
    case connectionFailed(summary: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .incompleteConfiguration:
            L10n.text("azureOpenAI.error.incompleteConfiguration")
        case .invalidEndpoint:
            L10n.text("azureOpenAI.error.invalidEndpoint")
        case .connectionFailed(let message, _):
            L10n.text("azureOpenAI.error.connectionFailed", message)
        }
    }

    var diagnosticDescription: String {
        switch self {
        case .incompleteConfiguration:
            L10n.text("azureOpenAI.error.incompleteConfiguration")
        case .invalidEndpoint:
            L10n.text("azureOpenAI.error.invalidEndpoint")
        case .connectionFailed(_, let detail):
            detail
        }
    }
}

actor AzureOpenAIRealtimeTranslationService {
    private static let apiVersion = "2025-04-01-preview"
    private static let maximumRequestAttempts = 5
    private static let maximumPreviousSourceTextCount = 5
    private var configuration: AzureOpenAIRealtimeTranslationConfiguration?
    private var queuedTranslationTask: Task<AzureOpenAIRealtimeTranslationResult?, Never>?
    private var recentSourceTexts: [String] = []
    private var isStarted = false
    var onDiagnostic: (@Sendable (AzureOpenAIRealtimeTranslationDiagnostic) -> Void)?

    func setOnDiagnostic(_ handler: (@Sendable (AzureOpenAIRealtimeTranslationDiagnostic) -> Void)?) {
        onDiagnostic = handler
    }

    func start(configuration: AzureOpenAIRealtimeTranslationConfiguration) async throws {
        await stop()

        guard configuration.isConfigured else {
            throw AzureOpenAIRealtimeTranslationError.incompleteConfiguration
        }

        _ = try Self.requestURL(for: configuration)
        self.configuration = configuration
        recentSourceTexts.removeAll()
        isStarted = true
    }

    func stop() async {
        isStarted = false
        configuration = nil
        queuedTranslationTask?.cancel()
        queuedTranslationTask = nil
        recentSourceTexts.removeAll()
    }

    func normalizeAndTranslate(
        transcriptDrafts: [AccurateCaptionTranscriptDraft],
        inputLanguage: InputLanguage,
        phraseHints: [String],
        targetLanguageIDs: Set<String>
    ) async -> AzureOpenAIRealtimeTranslationResult? {
        guard isStarted,
              let configuration
        else {
            return nil
        }

        let normalizedTranscriptDrafts = transcriptDrafts
            .map { AccurateCaptionTranscriptDraft(providerID: $0.providerID, text: $0.normalizedText) }
        guard normalizedTranscriptDrafts.contains(where: { !$0.normalizedText.isEmpty }) else {
            return nil
        }

        let targetLanguages = configuration.targetLanguages.filter { targetLanguageIDs.contains($0.id) }
        let previousTask = queuedTranslationTask
        let currentTask = Task<AzureOpenAIRealtimeTranslationResult?, Never> { [weak self] in
            _ = await previousTask?.value
            guard let self else {
                return nil
            }

            return await self.performNormalizeAndTranslate(
                transcriptDrafts: normalizedTranscriptDrafts,
                inputLanguage: inputLanguage,
                phraseHints: phraseHints,
                targetLanguages: targetLanguages,
                configuration: configuration
            )
        }
        queuedTranslationTask = currentTask
        return await currentTask.value
    }

    private func performNormalizeAndTranslate(
        transcriptDrafts: [AccurateCaptionTranscriptDraft],
        inputLanguage: InputLanguage,
        phraseHints: [String],
        targetLanguages: [SpeechOutputLanguage],
        configuration: AzureOpenAIRealtimeTranslationConfiguration
    ) async -> AzureOpenAIRealtimeTranslationResult? {
        do {
            let previousSourceTexts = recentSourceTexts
            let result = try await requestNormalizationAndTranslationsWithRetry(
                transcriptDrafts: transcriptDrafts,
                previousSourceTexts: previousSourceTexts,
                inputLanguage: inputLanguage,
                phraseHints: phraseHints,
                targetLanguages: targetLanguages,
                configuration: configuration
            )
            let sourceText = result.sourceText
            let translations = result.translations
            appendRecentSourceText(sourceText)

            let missingLanguageIDs = targetLanguages
                .map(\.id)
                .filter { translations[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false }
            if !missingLanguageIDs.isEmpty {
                emitDiagnostic(
                    level: .warning,
                    detail: Self.translationMissingLanguagesDetail(
                        targetLanguages: targetLanguages.map(\.id),
                        returnedLanguages: Array(translations.keys),
                        missingLanguages: missingLanguageIDs
                    )
                )
            }

            return AzureOpenAIRealtimeTranslationResult(sourceText: sourceText, translations: translations)
        } catch {
            emitDiagnostic(level: .error, detail: Self.errorDetail(error, phase: "translationRequest"))
            return nil
        }
    }

    private func requestNormalizationAndTranslationsWithRetry(
        transcriptDrafts: [AccurateCaptionTranscriptDraft],
        previousSourceTexts: [String],
        inputLanguage: InputLanguage,
        phraseHints: [String],
        targetLanguages: [SpeechOutputLanguage],
        configuration: AzureOpenAIRealtimeTranslationConfiguration
    ) async throws -> AzureOpenAIRealtimeTranslationResult {
        var lastError: Error?

        for attempt in 1...Self.maximumRequestAttempts {
            do {
                return try await requestNormalizationAndTranslations(
                    transcriptDrafts: transcriptDrafts,
                    previousSourceTexts: previousSourceTexts,
                    inputLanguage: inputLanguage,
                    phraseHints: phraseHints,
                    targetLanguages: targetLanguages,
                    configuration: configuration
                )
            } catch {
                lastError = error

                guard attempt < Self.maximumRequestAttempts,
                      let delayNanoseconds = Self.retryDelayNanoseconds(for: error, attempt: attempt)
                else {
                    break
                }

                emitDiagnostic(
                    level: .warning,
                    detail: [
                        "phase=translationRetry",
                        "reason=rateLimited",
                        "attempt=\(attempt)",
                        "nextAttempt=\(attempt + 1)",
                        "delayMs=\(delayNanoseconds / 1_000_000)",
                    ].joined(separator: "; ")
                )
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }

        throw lastError ?? AzureOpenAITextTranslationError.invalidResponse(detail: "reason=missingRetryError")
    }

    private func requestNormalizationAndTranslations(
        transcriptDrafts: [AccurateCaptionTranscriptDraft],
        previousSourceTexts: [String],
        inputLanguage: InputLanguage,
        phraseHints: [String],
        targetLanguages: [SpeechOutputLanguage],
        configuration: AzureOpenAIRealtimeTranslationConfiguration
    ) async throws -> AzureOpenAIRealtimeTranslationResult {
        var request = URLRequest(url: try Self.requestURL(for: configuration))
        request.httpMethod = "POST"
        request.setValue(configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "api-key")
        request.setValue("LiveCaptionPortal", forHTTPHeaderField: "OpenAI-Safety-Identifier")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "messages": [
                [
                    "role": "system",
                    "content": Self.systemPrompt(
                        inputLanguage: inputLanguage,
                        phraseHints: phraseHints,
                        targetLanguages: targetLanguages
                    ),
                ],
                [
                    "role": "user",
                    "content": try Self.userContent(
                        transcriptDrafts: transcriptDrafts,
                        previousSourceTexts: previousSourceTexts
                    ),
                ],
            ],
            "temperature": 0,
            "response_format": [
                "type": "json_object",
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AzureOpenAITextTranslationError.invalidResponse(detail: "reason=missingHTTPResponse")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AzureOpenAITextTranslationError.httpError(
                statusCode: httpResponse.statusCode,
                detail: Self.responseErrorDetail(from: data),
                retryAfterSeconds: Self.retryAfterSeconds(from: httpResponse)
            )
        }

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AzureOpenAITextTranslationError.invalidResponse(detail: "reason=invalidJSON; responseBytes=\(data.count)")
        }

        guard let choices = payload["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw AzureOpenAITextTranslationError.invalidResponse(
                detail: Self.invalidResponseDetail(payload: payload, contentChars: nil)
            )
        }

        guard let contentData = content.data(using: .utf8),
              let contentPayload = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let sourceText = contentPayload["sourceText"] as? String,
              let translationsPayload = contentPayload["translations"] as? [String: String]
        else {
            throw AzureOpenAITextTranslationError.invalidResponse(
                detail: Self.invalidResponseDetail(payload: payload, contentChars: content.count)
            )
        }

        let normalizedSourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSourceText.isEmpty else {
            throw AzureOpenAITextTranslationError.invalidResponse(detail: "reason=missingSourceText")
        }

        let translations = translationsPayload.compactMapValues { value in
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedValue.isEmpty ? nil : normalizedValue
        }
        return AzureOpenAIRealtimeTranslationResult(sourceText: normalizedSourceText, translations: translations)
    }

    private static func requestURL(for configuration: AzureOpenAIRealtimeTranslationConfiguration) throws -> URL {
        let endpoint = configuration.normalizedEndpointURLString
        let deploymentName = configuration.translationDeploymentName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard var components = URLComponents(string: endpoint) else {
            throw AzureOpenAIRealtimeTranslationError.invalidEndpoint
        }

        guard components.scheme == "https" || components.scheme == "wss" else {
            throw AzureOpenAIRealtimeTranslationError.invalidEndpoint
        }

        components.scheme = "https"
        components.path = "/openai/deployments/\(deploymentName)/chat/completions"
        components.queryItems = [
            URLQueryItem(name: "api-version", value: Self.apiVersion),
        ]

        guard let url = components.url else {
            throw AzureOpenAIRealtimeTranslationError.invalidEndpoint
        }

        return url
    }

    private static func systemPrompt(
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
        Produce one faithful source-language subtitle in \(inputLanguage.azureOpenAITextNormalizationName) as sourceText, then translate sourceText into the requested languages.
        Choose sourceText from transcriptCandidates. Prefer the Azure OpenAI candidate when it is present and coherent.
        Use the Azure Speech candidate only as secondary evidence. Ignore Azure Speech when it is clearly garbled, phonetically mistranscribed, or conflicts with stable previousSourceTexts.
        Use Azure Speech as the fallback source only when the Azure OpenAI candidate is missing, empty, or clearly damaged.
        Use previousSourceTexts and vocabulary hints only as conservative source-language context for homophones, near-sound words, segmentation, code-switching, topic continuity, spelling, capitalization, punctuation, and Traditional Chinese normalization.
        Treat previousSourceTexts as source-language context, not translated evidence. Preserve the current talk topic across adjacent subtitles when resolving ambiguous candidates.
        Preserve the heard language form in sourceText when it is supported by the candidates or previousSourceTexts.
        Do not replace code-switched text with phonetically similar words in another language.
        If a candidate phrase is unnatural in the source language and a homophone or near-sound alternative is supported by context, use the natural source-language alternative.
        If a code-switch phrase is unnatural in the surrounding source-language context, and a near-sound code-switch phrase is supported by context, use the contextual phrase.
        For Mandarin sourceText, be especially careful when speech includes English code-switching. Do not normalize an ambiguous candidate into a meaning that changes the current topic unless the current candidates clearly support that topic shift.
        Do not add content the speaker did not say, copy from previousSourceTexts, beautify wording, formalize spoken language, paraphrase, summarize, expand, or censor.
        If uncertain, keep the most reliable candidate wording.
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

    private static func userContent(
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
        return String(decoding: data, as: UTF8.self)
    }

    private static func normalizedPreviousSourceTexts(_ sourceTexts: [String]) -> [String] {
        Array(
            sourceTexts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .suffix(maximumPreviousSourceTextCount)
        )
    }

    private func appendRecentSourceText(_ sourceText: String) {
        let normalizedSourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSourceText.isEmpty else {
            return
        }

        recentSourceTexts.append(normalizedSourceText)
        if recentSourceTexts.count > Self.maximumPreviousSourceTextCount {
            recentSourceTexts.removeFirst(recentSourceTexts.count - Self.maximumPreviousSourceTextCount)
        }
    }

    private static func responseErrorDetail(from data: Data) -> String {
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

    private func emitDiagnostic(level: AzureOpenAIRealtimeTranslationDiagnostic.Level, detail: String) {
        onDiagnostic?(AzureOpenAIRealtimeTranslationDiagnostic(level: level, detail: detail))
    }

    private static func translationMissingLanguagesDetail(
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

    private static func invalidResponseDetail(payload: [String: Any], contentChars: Int?) -> String {
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

    private static func errorDetail(_ error: Error, phase: String) -> String {
        switch error {
        case let error as AzureOpenAITextTranslationError:
            "phase=\(phase); \(error.diagnosticDescription)"
        default:
            "phase=\(phase); error=\(error.localizedDescription)"
        }
    }

    private static func retryAfterSeconds(from response: HTTPURLResponse) -> Double? {
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

    private static func retryDelayNanoseconds(for error: Error, attempt: Int) -> UInt64? {
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

private enum AzureOpenAITextTranslationError: Error {
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
