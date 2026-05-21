import Foundation

extension AzureOpenAIRealtimeTranslationService {
    func requestNormalizationAndTranslationsWithRetry(
        requestContext: TranslationRequestContext
    ) async throws -> AzureOpenAIRealtimeTranslationResult {
        var lastError: Error?

        for attempt in 1...Self.maximumRequestAttempts {
            do {
                return try await requestNormalizationAndTranslations(
                    requestContext: requestContext
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

    func requestNormalizationAndTranslations(
        requestContext: TranslationRequestContext
    ) async throws -> AzureOpenAIRealtimeTranslationResult {
        let request = try Self.request(for: requestContext)
        let (data, response) = try await URLSession.shared.data(for: request)
        return try Self.translationResult(from: data, response: response)
    }

    static func request(for requestContext: TranslationRequestContext) throws -> URLRequest {
        let configuration = requestContext.configuration
        var request = URLRequest(url: try requestURL(for: configuration))
        request.httpMethod = "POST"
        request.setValue(
            configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            forHTTPHeaderField: "api-key"
        )
        request.setValue("LiveCaptionPortal", forHTTPHeaderField: "OpenAI-Safety-Identifier")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(for: requestContext))
        return request
    }

    static func requestBody(for requestContext: TranslationRequestContext) throws -> [String: Any] {
        [
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt(
                        inputLanguage: requestContext.inputLanguage,
                        phraseHints: requestContext.phraseHints,
                        targetLanguages: requestContext.targetLanguages
                    ),
                ],
                [
                    "role": "user",
                    "content": try userContent(
                        transcriptDrafts: requestContext.transcriptDrafts,
                        previousSourceTexts: requestContext.previousSourceTexts
                    ),
                ],
            ],
            "temperature": 0,
            "response_format": [
                "type": "json_object",
            ],
        ]
    }

    static func translationResult(
        from data: Data,
        response: URLResponse
    ) throws -> AzureOpenAIRealtimeTranslationResult {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AzureOpenAITextTranslationError.invalidResponse(detail: "reason=missingHTTPResponse")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AzureOpenAITextTranslationError.httpError(
                statusCode: httpResponse.statusCode,
                detail: responseErrorDetail(from: data),
                retryAfterSeconds: retryAfterSeconds(from: httpResponse)
            )
        }

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AzureOpenAITextTranslationError.invalidResponse(
                detail: "reason=invalidJSON; responseBytes=\(data.count)"
            )
        }

        guard let choices = payload["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw AzureOpenAITextTranslationError.invalidResponse(
                detail: invalidResponseDetail(payload: payload, contentChars: nil)
            )
        }

        guard let contentData = content.data(using: .utf8),
              let contentPayload = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
              let sourceText = contentPayload["sourceText"] as? String,
              let translationsPayload = contentPayload["translations"] as? [String: String]
        else {
            throw AzureOpenAITextTranslationError.invalidResponse(
                detail: invalidResponseDetail(payload: payload, contentChars: content.count)
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

    static func requestURL(for configuration: AzureOpenAITranslationConfig) throws -> URL {
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
}
