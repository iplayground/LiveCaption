import Foundation

struct AzureOpenAIRealtimeTranscriptionConfiguration: Equatable, Sendable {
    let endpointURLString: String
    let transcriptionDeploymentName: String
    let apiKey: String
    let inputLanguage: InputLanguage
    let phraseHints: [String]

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
    let openAIText: String
    let speechText: String
    let offsetTicks: UInt64
    let durationTicks: UInt64

    var transcriptDrafts: [AccurateCaptionTranscriptDraft] {
        [
            AccurateCaptionTranscriptDraft(providerID: "gpt-4o-mini-transcribe", text: openAIText),
            AccurateCaptionTranscriptDraft(providerID: "azure-speech", text: speechText),
        ]
    }
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
    private static let sampleRate = 24_000
    private static let bytesPerSample = MemoryLayout<Int16>.size
    private static let audioPaddingMilliseconds: UInt64 = 250
    private static let apiVersion = "2025-04-01-preview"
    private static let transcriptionModelName = "gpt-4o-mini-transcribe"
    private var configuration: AzureOpenAIRealtimeTranscriptionConfiguration?
    private var audioBuffer = Data()
    private var bufferedAudioMilliseconds: UInt64 = 0
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

        _ = try Self.requestURL(for: configuration)
        self.configuration = configuration
        audioBuffer.removeAll(keepingCapacity: true)
        bufferedAudioMilliseconds = 0
        isStarted = true
    }

    func stop() async {
        isStarted = false
        configuration = nil
        audioBuffer.removeAll(keepingCapacity: false)
        bufferedAudioMilliseconds = 0
    }

    func appendPCM16Audio(_ audio: Data) async {
        guard isStarted, !audio.isEmpty else {
            return
        }

        audioBuffer.append(audio)
        bufferedAudioMilliseconds += Self.audioMilliseconds(forPCM16ByteCount: audio.count)
    }

    func transcribeAudio(for event: RecognizedCaptionEvent) async {
        guard isStarted, let configuration else {
            return
        }

        let speechText = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let segmentStartMilliseconds = event.offsetTicks / Self.ticksPerMillisecond
        let segmentDurationMilliseconds = max(event.durationTicks / Self.ticksPerMillisecond, 1)
        let paddedStartMilliseconds = segmentStartMilliseconds > Self.audioPaddingMilliseconds
            ? segmentStartMilliseconds - Self.audioPaddingMilliseconds
            : 0
        let paddedEndMilliseconds = min(
            bufferedAudioMilliseconds,
            segmentStartMilliseconds + segmentDurationMilliseconds + Self.audioPaddingMilliseconds
        )

        guard paddedEndMilliseconds > paddedStartMilliseconds else {
            emitDiagnostic(
                level: .warning,
                detail: "phase=transcriptionSkipped; reason=missingAudio; audioStartMs=\(segmentStartMilliseconds); audioDurationMs=\(segmentDurationMilliseconds); bufferedAudioMs=\(bufferedAudioMilliseconds)"
            )
            return
        }

        let audio = audioSlice(
            startMilliseconds: paddedStartMilliseconds,
            endMilliseconds: paddedEndMilliseconds
        )
        guard !audio.isEmpty else {
            emitDiagnostic(
                level: .warning,
                detail: "phase=transcriptionSkipped; reason=emptyAudioSlice; audioStartMs=\(segmentStartMilliseconds); audioDurationMs=\(segmentDurationMilliseconds); bufferedAudioMs=\(bufferedAudioMilliseconds)"
            )
            return
        }

        do {
            let text = try await transcribe(
                wavAudio: Self.wavData(fromPCM16Mono24k: audio),
                configuration: configuration
            )
            let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            emitTranscriptDiagnostic(
                text: normalizedText,
                audioStartMilliseconds: segmentStartMilliseconds,
                audioEndMilliseconds: segmentStartMilliseconds + segmentDurationMilliseconds
            )

            guard !normalizedText.isEmpty else {
                publishTranscriptionResult(openAIText: normalizedText, speechText: speechText, event: event)
                return
            }

            publishTranscriptionResult(openAIText: normalizedText, speechText: speechText, event: event)
        } catch {
            emitDiagnostic(level: .error, detail: Self.errorDetail(error, phase: "transcriptionRequest"))
            publishTranscriptionResult(openAIText: "", speechText: speechText, event: event)
        }
    }

    private func publishTranscriptionResult(
        openAIText: String,
        speechText: String,
        event: RecognizedCaptionEvent
    ) {
        guard !openAIText.isEmpty || !speechText.isEmpty else {
            return
        }

        onTranscription?(
            AzureOpenAIRealtimeTranscriptionResult(
                openAIText: openAIText,
                speechText: speechText,
                offsetTicks: event.offsetTicks,
                durationTicks: event.durationTicks
            )
        )
    }

    private func audioSlice(startMilliseconds: UInt64, endMilliseconds: UInt64) -> Data {
        let startByte = Self.byteOffset(forAudioMilliseconds: startMilliseconds)
        let endByte = min(Self.byteOffset(forAudioMilliseconds: endMilliseconds), audioBuffer.count)
        guard startByte < endByte else {
            return Data()
        }

        return audioBuffer.subdata(in: startByte..<endByte)
    }

    private func transcribe(
        wavAudio: Data,
        configuration: AzureOpenAIRealtimeTranscriptionConfiguration
    ) async throws -> String {
        var request = URLRequest(url: try Self.requestURL(for: configuration))
        let boundary = "LiveCaptionBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        request.httpMethod = "POST"
        request.setValue(configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "api-key")
        request.setValue("LiveCaptionPortal", forHTTPHeaderField: "OpenAI-Safety-Identifier")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = Self.multipartBody(
            boundary: boundary,
            wavAudio: wavAudio,
            languageCode: configuration.inputLanguage.azureOpenAITranscriptionLanguageCode,
            prompt: Self.transcriptionPrompt(for: configuration)
        )
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AzureOpenAIAudioTranscriptionError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AzureOpenAIAudioTranscriptionError.httpError(
                statusCode: httpResponse.statusCode,
                detail: Self.responseErrorDetail(from: data)
            )
        }

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = payload["text"] as? String
        else {
            throw AzureOpenAIAudioTranscriptionError.invalidResponse
        }

        return text
    }

    private func emitTranscriptDiagnostic(
        text: String,
        audioStartMilliseconds: UInt64,
        audioEndMilliseconds: UInt64
    ) {
        let replacementCharacterCount = Self.replacementCharacterCount(in: text)
        guard text.isEmpty || replacementCharacterCount > 0 else {
            return
        }

        let detailParts = [
            "phase=transcriptionCompleted",
            "endpoint=audioTranscriptions",
            "issue=\(text.isEmpty ? "emptyTranscript" : "replacementCharacters")",
            "transcriptChars=\(text.count)",
            "transcriptReplacementCount=\(replacementCharacterCount)",
            "audioStartMs=\(audioStartMilliseconds)",
            "audioEndMs=\(audioEndMilliseconds)",
        ]
        emitDiagnostic(level: .warning, detail: detailParts.joined(separator: "; "))
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

        components.scheme = "https"
        components.path = "/openai/deployments/\(deploymentName)/audio/transcriptions"
        components.queryItems = [
            URLQueryItem(name: "api-version", value: Self.apiVersion),
        ]

        guard let url = components.url else {
            throw AzureOpenAIRealtimeTranslationError.invalidEndpoint
        }

        return url
    }

    private static func multipartBody(
        boundary: String,
        wavAudio: Data,
        languageCode: String,
        prompt: String
    ) -> Data {
        var body = Data()
        appendFormField(name: "model", value: Self.transcriptionModelName, boundary: boundary, to: &body)
        appendFormField(name: "language", value: languageCode, boundary: boundary, to: &body)
        appendFormField(name: "prompt", value: prompt, boundary: boundary, to: &body)
        appendFormField(name: "response_format", value: "json", boundary: boundary, to: &body)
        appendFormField(name: "temperature", value: "0", boundary: boundary, to: &body)
        appendFileField(
            name: "file",
            filename: "caption-segment.wav",
            contentType: "audio/wav",
            data: wavAudio,
            boundary: boundary,
            to: &body
        )
        body.append("--\(boundary)--\r\n")
        return body
    }

    private static func appendFormField(name: String, value: String, boundary: String, to body: inout Data) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append("\(value)\r\n")
    }

    private static func appendFileField(
        name: String,
        filename: String,
        contentType: String,
        data: Data,
        boundary: String,
        to body: inout Data
    ) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    private static func wavData(fromPCM16Mono24k pcmAudio: Data) -> Data {
        let sampleRate = UInt32(Self.sampleRate)
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channelCount) * UInt32(bitsPerSample / 8)
        let blockAlign = channelCount * (bitsPerSample / 8)
        let dataSize = UInt32(pcmAudio.count)
        let riffSize = UInt32(36) + dataSize

        var wav = Data()
        wav.append("RIFF")
        wav.append(riffSize.littleEndianData)
        wav.append("WAVE")
        wav.append("fmt ")
        wav.append(UInt32(16).littleEndianData)
        wav.append(UInt16(1).littleEndianData)
        wav.append(channelCount.littleEndianData)
        wav.append(sampleRate.littleEndianData)
        wav.append(byteRate.littleEndianData)
        wav.append(blockAlign.littleEndianData)
        wav.append(bitsPerSample.littleEndianData)
        wav.append("data")
        wav.append(dataSize.littleEndianData)
        wav.append(pcmAudio)
        return wav
    }

    private static func transcriptionPrompt(for configuration: AzureOpenAIRealtimeTranscriptionConfiguration) -> String {
        var lines: [String] = []
        if let languagePrompt = configuration.inputLanguage.azureOpenAIRealtimePrompt {
            lines.append(languagePrompt)
        }
        lines.append("Never output the Unicode replacement character �. If speech is unclear, choose the most likely readable word instead.")

        let phraseHints = configuration.phraseHints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !phraseHints.isEmpty {
            lines.append("Use these likely vocabulary terms as canonical spellings when heard.")
            lines.append("Do not translate, localize, or partially replace Latin brand names with CJK characters.")
            lines.append("If the audio sounds like one of these terms, output the full term exactly as listed, preserving capitalization.")
            lines.append("Likely vocabulary: \(phraseHints.joined(separator: ", ")).")
        }

        return lines.joined(separator: "\n")
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

    private static func errorDetail(_ error: Error, phase: String) -> String {
        switch error {
        case let error as AzureOpenAIAudioTranscriptionError:
            "phase=\(phase); \(error.diagnosticDescription)"
        default:
            "phase=\(phase); error=\(error.localizedDescription)"
        }
    }

    private static func replacementCharacterCount(in text: String) -> Int {
        text.unicodeScalars.filter { $0.value == 0xFFFD }.count
    }

    private static func audioMilliseconds(forPCM16ByteCount byteCount: Int) -> UInt64 {
        let sampleCount = byteCount / Self.bytesPerSample
        return UInt64((Double(sampleCount) / Double(Self.sampleRate) * 1_000).rounded())
    }

    private static func byteOffset(forAudioMilliseconds milliseconds: UInt64) -> Int {
        let sampleCount = Int((Double(milliseconds) / 1_000 * Double(Self.sampleRate)).rounded())
        return sampleCount * Self.bytesPerSample
    }
}

private enum AzureOpenAIAudioTranscriptionError: Error {
    case httpError(statusCode: Int, detail: String)
    case invalidResponse

    var diagnosticDescription: String {
        switch self {
        case .httpError(let statusCode, let detail):
            "httpStatus=\(statusCode); \(detail)"
        case .invalidResponse:
            "error=invalidResponse"
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
}

private extension InputLanguage {
    nonisolated var azureOpenAITranscriptionLanguageCode: String {
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
