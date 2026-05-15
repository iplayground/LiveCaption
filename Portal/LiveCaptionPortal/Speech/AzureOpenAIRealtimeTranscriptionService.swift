import Foundation

struct AzureOpenAIRealtimeTranscriptionConfiguration: Equatable, Sendable {
    let endpointURLString: String
    let transcriptionDeploymentName: String
    let apiKey: String
    let inputLanguage: InputLanguage
    let sentenceSilenceTimeoutMilliseconds: Int

    nonisolated var isConfigured: Bool {
        !normalizedEndpointURLString.isEmpty
            && !transcriptionDeploymentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

struct AzureOpenAIRealtimeTranscriptionResult: Equatable, Sendable {
    let text: String
    let offsetTicks: UInt64
    let durationTicks: UInt64
}

struct AzureOpenAIRealtimeTranscriptionDiagnostic: Equatable, Sendable {
    enum Level: Equatable, Sendable {
        case info
        case warning
        case error
    }

    let level: Level
    let detail: String
}

actor AzureOpenAIRealtimeTranscriptionService {
    var onTranscription: (@Sendable (AzureOpenAIRealtimeTranscriptionResult) -> Void)?
    var onDiagnostic: (@Sendable (AzureOpenAIRealtimeTranscriptionDiagnostic) -> Void)?

    private static let ticksPerMillisecond: UInt64 = 10_000
    private static let minimumDurationMilliseconds: UInt64 = 500
    private var session: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var transcriptBuffer = ""
    private var lastCompletedEndMilliseconds: UInt64 = 0
    private var observedUnhandledEventTypes: Set<String> = []
    private var isStarted = false

    func setOnTranscription(_ handler: (@Sendable (AzureOpenAIRealtimeTranscriptionResult) -> Void)?) {
        onTranscription = handler
    }

    func setOnDiagnostic(_ handler: (@Sendable (AzureOpenAIRealtimeTranscriptionDiagnostic) -> Void)?) {
        onDiagnostic = handler
    }

    func start(configuration: AzureOpenAIRealtimeTranscriptionConfiguration) async throws {
        await stop()

        guard configuration.isConfigured else {
            throw AzureOpenAIRealtimeTranslationError.incompleteConfiguration
        }

        let requestURL = try Self.requestURL(for: configuration)
        var request = URLRequest(url: requestURL)
        request.setValue(configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "api-key")
        request.setValue("LiveCaptionPortal", forHTTPHeaderField: "OpenAI-Safety-Identifier")

        let task = URLSession.shared.webSocketTask(with: request)
        session = task
        task.resume()

        do {
            try await sendSessionUpdate(to: task, configuration: configuration)
        } catch {
            await stop()
            throw Self.connectionFailedError(
                error,
                task: task,
                phase: "session.update transcription",
                deploymentName: configuration.transcriptionDeploymentName
            )
        }

        receiveTask = Task { [weak self] in
            await self?.receiveMessages(task: task)
        }
        isStarted = true
    }

    func stop() async {
        isStarted = false
        receiveTask?.cancel()
        receiveTask = nil
        session?.cancel(with: .goingAway, reason: nil)
        session = nil
        transcriptBuffer = ""
        lastCompletedEndMilliseconds = 0
        observedUnhandledEventTypes.removeAll()
    }

    func appendPCM16Audio(_ audio: Data) async {
        guard isStarted, !audio.isEmpty else {
            return
        }

        let payload: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": audio.base64EncodedString(),
        ]

        guard let message = Self.jsonString(from: payload) else {
            return
        }

        try? await session?.send(.string(message))
    }

    private func sendSessionUpdate(
        to task: URLSessionWebSocketTask,
        configuration: AzureOpenAIRealtimeTranscriptionConfiguration
    ) async throws {
        var transcription: [String: Any] = [
            "model": configuration.transcriptionDeploymentName.trimmingCharacters(in: .whitespacesAndNewlines),
            "language": configuration.inputLanguage.azureOpenAIRealtimeLanguageCode,
        ]
        if let prompt = configuration.inputLanguage.azureOpenAIRealtimePrompt {
            transcription["prompt"] = prompt
        }

        let payload: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24_000,
                        ],
                        "transcription": transcription,
                        "turn_detection": [
                            "type": "server_vad",
                            "threshold": 0.5,
                            "prefix_padding_ms": 300,
                            "silence_duration_ms": configuration.sentenceSilenceTimeoutMilliseconds,
                        ],
                    ],
                ],
            ],
        ]

        guard let message = Self.jsonString(from: payload) else {
            return
        }

        try await task.send(.string(message))
    }

    private func receiveMessages(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                await handle(message: message)
            } catch {
                guard isStarted, !Task.isCancelled else {
                    return
                }
                emitDiagnostic(level: .warning, detail: "phase=receive; error=\(error.localizedDescription)")
                return
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) async {
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
              let type = payload["type"] as? String
        else {
            emitDiagnostic(level: .warning, detail: "phase=message; error=Invalid Azure OpenAI transcription event.")
            return
        }

        switch type {
        case "error", "session.error":
            emitDiagnostic(level: .error, detail: Self.serverErrorDetail(from: payload, phase: "serverEvent"))
        case "session.output_transcript.delta", "conversation.item.input_audio_transcription.delta":
            recordTranscriptDelta(payload)
        case "session.output_transcript.done",
             "session.output_transcript.completed",
             "conversation.item.input_audio_transcription.completed":
            publishTranscript(payload)
        case "input_audio_buffer.speech_started",
             "input_audio_buffer.speech_stopped",
             "input_audio_buffer.committed",
             "session.updated",
             "session.created",
             "transcription_session.updated",
             "transcription_session.created",
             "conversation.item.done",
             "conversation.item.added":
            break
        default:
            recordUnhandledEventType(type, payload: payload)
        }
    }

    private func recordTranscriptDelta(_ payload: [String: Any]) {
        guard let delta = payload["delta"] as? String, !delta.isEmpty else {
            return
        }

        transcriptBuffer.append(delta)
    }

    private func publishTranscript(_ payload: [String: Any]) {
        let text = Self.normalizedTranscriptionText(payload["transcript"] as? String, fallback: transcriptBuffer)
        guard !text.isEmpty else {
            transcriptBuffer = ""
            return
        }

        let startMilliseconds = Self.unsignedMilliseconds(from: payload["audio_start_ms"]) ?? lastCompletedEndMilliseconds
        let endMilliseconds = Self.unsignedMilliseconds(from: payload["audio_end_ms"])
            ?? startMilliseconds + max(Self.minimumDurationMilliseconds, UInt64(text.count * 120))
        let normalizedEndMilliseconds = max(endMilliseconds, startMilliseconds + Self.minimumDurationMilliseconds)
        lastCompletedEndMilliseconds = normalizedEndMilliseconds

        let result = AzureOpenAIRealtimeTranscriptionResult(
            text: text,
            offsetTicks: startMilliseconds * Self.ticksPerMillisecond,
            durationTicks: (normalizedEndMilliseconds - startMilliseconds) * Self.ticksPerMillisecond
        )
        transcriptBuffer = ""
        onTranscription?(result)
    }

    private func recordUnhandledEventType(_ type: String, payload: [String: Any]) {
        guard !observedUnhandledEventTypes.contains(type), observedUnhandledEventTypes.count < 20 else {
            return
        }

        observedUnhandledEventTypes.insert(type)
        emitDiagnostic(level: .info, detail: "event=unhandled; type=\(type); keys=\(Self.keysDescription(payload))")
    }

    private func emitDiagnostic(level: AzureOpenAIRealtimeTranscriptionDiagnostic.Level, detail: String) {
        onDiagnostic?(AzureOpenAIRealtimeTranscriptionDiagnostic(level: level, detail: detail))
    }

    private static func requestURL(for configuration: AzureOpenAIRealtimeTranscriptionConfiguration) throws -> URL {
        let endpoint = configuration.normalizedEndpointURLString
        let deploymentName = configuration.transcriptionDeploymentName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard var components = URLComponents(string: endpoint) else {
            throw AzureOpenAIRealtimeTranslationError.invalidEndpoint
        }

        guard components.scheme == "https" || components.scheme == "wss" else {
            throw AzureOpenAIRealtimeTranslationError.invalidEndpoint
        }

        components.scheme = "wss"
        components.path = "/openai/v1/realtime"
        components.queryItems = [
            URLQueryItem(name: "deployment", value: deploymentName),
            URLQueryItem(name: "intent", value: "transcription"),
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

    private static func normalizedTranscriptionText(_ text: String?, fallback: String?) -> String {
        let normalizedText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !normalizedText.isEmpty {
            return normalizedText
        }

        return fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func unsignedMilliseconds(from value: Any?) -> UInt64? {
        switch value {
        case let value as UInt64:
            value
        case let value as Int where value >= 0:
            UInt64(value)
        case let value as Double where value >= 0:
            UInt64(value.rounded())
        case let value as String:
            UInt64(value)
        default:
            nil
        }
    }

    private static func keysDescription(_ payload: [String: Any]) -> String {
        payload.keys.sorted().joined(separator: ",")
    }

    private static func serverErrorDetail(from payload: [String: Any], phase: String) -> String {
        let errorPayload = payload["error"] as? [String: Any]
        let type = errorPayload?["type"] as? String
        let code = errorPayload?["code"] as? String
        let message = errorPayload?["message"] as? String ?? "Azure OpenAI realtime server error."
        let param = errorPayload?["param"] as? String

        var details = [
            "phase=\(phase)",
            "serverError=\(message)",
        ]
        if let type, !type.isEmpty {
            details.append("type=\(type)")
        }
        if let code, !code.isEmpty {
            details.append("code=\(code)")
        }
        if let param, !param.isEmpty {
            details.append("param=\(param)")
        }

        return details.joined(separator: "; ")
    }

    private static func connectionFailedError(
        _ error: Error,
        task: URLSessionWebSocketTask,
        phase: String,
        deploymentName: String
    ) -> AzureOpenAIRealtimeTranslationError {
        let summary = error.localizedDescription
        let nsError = error as NSError
        var details = [
            "phase=\(phase)",
            "deployment=\(deploymentName.trimmingCharacters(in: .whitespacesAndNewlines))",
            "closeCode=\(task.closeCode.rawValue)",
            "errorDomain=\(nsError.domain)",
            "errorCode=\(nsError.code)",
            "error=\(summary)",
        ]

        if let response = nsError.userInfo["NSErrorFailingURLResponseKey"] as? HTTPURLResponse {
            details.append("httpStatus=\(response.statusCode)")
        }

        return .connectionFailed(summary: summary, detail: details.joined(separator: "; "))
    }
}

private extension InputLanguage {
    nonisolated var azureOpenAIRealtimeLanguageCode: String {
        switch self {
        case .mandarin:
            "zh"
        case .english:
            "en"
        }
    }

    nonisolated var azureOpenAIRealtimePrompt: String? {
        switch self {
        case .mandarin:
            "Transcribe Mandarin as Taiwan Traditional Chinese. Never output Simplified Chinese."
        case .english:
            nil
        }
    }
}
