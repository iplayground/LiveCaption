import Foundation

struct AzureOpenAIRealtimeTranslationConfiguration: Equatable, Sendable {
    let endpointURLString: String
    let deploymentName: String
    let apiKey: String
    let targetLanguages: [SpeechOutputLanguage]

    nonisolated var isConfigured: Bool {
        !normalizedEndpointURLString.isEmpty
            && !deploymentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !targetLanguages.isEmpty
    }

    nonisolated var normalizedEndpointURLString: String {
        var value = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}

enum AzureOpenAIRealtimeTranslationError: LocalizedError {
    case incompleteConfiguration
    case invalidEndpoint
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .incompleteConfiguration:
            L10n.text("azureOpenAI.error.incompleteConfiguration")
        case .invalidEndpoint:
            L10n.text("azureOpenAI.error.invalidEndpoint")
        case .connectionFailed(let message):
            L10n.text("azureOpenAI.error.connectionFailed", message)
        }
    }
}

actor AzureOpenAIRealtimeTranslationService {
    private var sessions: [String: URLSessionWebSocketTask] = [:]
    private var transcriptBuffers: [String: String] = [:]
    private var receiveTasks: [String: Task<Void, Never>] = [:]
    private var isStarted = false

    func start(configuration: AzureOpenAIRealtimeTranslationConfiguration) async throws {
        await stop()

        guard configuration.isConfigured else {
            throw AzureOpenAIRealtimeTranslationError.incompleteConfiguration
        }

        let requestURL = try Self.requestURL(for: configuration)
        let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let deploymentName = configuration.deploymentName.trimmingCharacters(in: .whitespacesAndNewlines)

        for language in configuration.targetLanguages {
            var request = URLRequest(url: requestURL)
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
            request.setValue("LiveCaptionPortal", forHTTPHeaderField: "OpenAI-Safety-Identifier")

            let task = URLSession.shared.webSocketTask(with: request)
            sessions[language.id] = task
            transcriptBuffers[language.id] = ""
            task.resume()

            do {
                try await sendSessionUpdate(to: task, language: language.azureOpenAIRealtimeLanguageCode)
            } catch {
                await stop()
                throw AzureOpenAIRealtimeTranslationError.connectionFailed(error.localizedDescription)
            }

            receiveTasks[language.id] = Task { [weak self] in
                await self?.receiveMessages(languageID: language.id, task: task)
            }
        }

        isStarted = true
        _ = deploymentName
    }

    func stop() async {
        isStarted = false
        receiveTasks.values.forEach { $0.cancel() }
        receiveTasks.removeAll()
        sessions.values.forEach { $0.cancel(with: .goingAway, reason: nil) }
        sessions.removeAll()
        transcriptBuffers.removeAll()
    }

    func appendPCM16Audio(_ audio: Data) async {
        guard isStarted, !audio.isEmpty else {
            return
        }

        let encodedAudio = audio.base64EncodedString()
        let payload: [String: Any] = [
            "type": "session.input_audio_buffer.append",
            "audio": encodedAudio,
        ]

        guard let message = Self.jsonString(from: payload) else {
            return
        }

        for task in sessions.values {
            try? await task.send(.string(message))
        }
    }

    func takeTranslations() async -> [String: String] {
        let translations = transcriptBuffers.compactMapValues { value -> String? in
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedValue.isEmpty ? nil : normalizedValue
        }

        transcriptBuffers.keys.forEach { transcriptBuffers[$0] = "" }
        return translations
    }

    private func sendSessionUpdate(to task: URLSessionWebSocketTask, language: String) async throws {
        let payload: [String: Any] = [
            "type": "session.update",
            "session": [
                "audio": [
                    "output": [
                        "language": language,
                    ],
                ],
            ],
        ]

        guard let message = Self.jsonString(from: payload) else {
            return
        }

        try await task.send(.string(message))
    }

    private func receiveMessages(languageID: String, task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                await handle(message: message, languageID: languageID)
            } catch {
                return
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message, languageID: String) async {
        let data: Data?
        switch message {
        case .string(let text):
            data = Data(text.utf8)
        case .data(let messageData):
            data = messageData
        @unknown default:
            data = nil
        }

        guard let data,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["type"] as? String == "session.output_transcript.delta",
              let delta = payload["delta"] as? String,
              !delta.isEmpty
        else {
            return
        }

        transcriptBuffers[languageID, default: ""].append(delta)
    }

    private static func requestURL(for configuration: AzureOpenAIRealtimeTranslationConfiguration) throws -> URL {
        let endpoint = configuration.normalizedEndpointURLString
        let deploymentName = configuration.deploymentName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard var components = URLComponents(string: endpoint) else {
            throw AzureOpenAIRealtimeTranslationError.invalidEndpoint
        }

        guard components.scheme == "https" || components.scheme == "wss" else {
            throw AzureOpenAIRealtimeTranslationError.invalidEndpoint
        }

        components.scheme = "wss"
        components.path = "/openai/v1/realtime/translations"
        components.queryItems = [
            URLQueryItem(name: "model", value: deploymentName)
        ]

        guard let url = components.url else {
            throw AzureOpenAIRealtimeTranslationError.invalidEndpoint
        }

        return url
    }

    private static func jsonString(from payload: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.sortedKeys, .withoutEscapingSlashes]
              )
        else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}

private extension SpeechOutputLanguage {
    nonisolated var azureOpenAIRealtimeLanguageCode: String {
        switch id {
        case "zh-Hant":
            "zh"
        default:
            id
        }
    }
}
