import Foundation

extension AzureOpenAIRealtimeTranscriptionService {
    func transcribe(
        wavAudio: Data,
        configuration: AzureOpenAITranscriptionConfig
    ) async throws -> String {
        var request = URLRequest(url: try Self.requestURL(for: configuration))
        let boundary = "LiveCaptionBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        request.httpMethod = "POST"
        request.setValue(
            configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            forHTTPHeaderField: "api-key"
        )
        request.setValue("LiveCaptionPortal", forHTTPHeaderField: "OpenAI-Safety-Identifier")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = Self.multipartBody(
            boundary: boundary,
            wavAudio: wavAudio,
            deploymentName: configuration.transcriptionDeploymentName,
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

    func emitTranscriptDiagnostic(
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

    func emitDiagnostic(level: AzureOpenAITranscriptionDiagnostic.Level, detail: String) {
        onDiagnostic?(AzureOpenAITranscriptionDiagnostic(level: level, detail: detail))
    }

    static func requestURL(for configuration: AzureOpenAITranscriptionConfig) throws -> URL {
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

    static func multipartBody(
        boundary: String,
        wavAudio: Data,
        deploymentName: String,
        languageCode: String,
        prompt: String
    ) -> Data {
        var body = Data()
        appendFormField(
            name: "model",
            value: deploymentName.trimmingCharacters(in: .whitespacesAndNewlines),
            boundary: boundary,
            to: &body
        )
        appendFormField(name: "language", value: languageCode, boundary: boundary, to: &body)
        appendFormField(name: "prompt", value: prompt, boundary: boundary, to: &body)
        appendFormField(name: "response_format", value: "json", boundary: boundary, to: &body)
        appendFormField(name: "temperature", value: "0", boundary: boundary, to: &body)
        appendFileField(
            MultipartFileField(
                name: "file",
                filename: "caption-segment.wav",
                contentType: "audio/wav",
                data: wavAudio
            ),
            boundary: boundary,
            to: &body
        )
        body.append("--\(boundary)--\r\n")
        return body
    }

    static func appendFormField(name: String, value: String, boundary: String, to body: inout Data) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append("\(value)\r\n")
    }

    static func appendFileField(_ field: MultipartFileField, boundary: String, to body: inout Data) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(field.name)\"; filename=\"\(field.filename)\"\r\n")
        body.append("Content-Type: \(field.contentType)\r\n\r\n")
        body.append(field.data)
        body.append("\r\n")
    }

    static func wavData(fromPCM16Mono24k pcmAudio: Data) -> Data {
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

    static func transcriptionPrompt(
        for configuration: AzureOpenAITranscriptionConfig
    ) -> String {
        var lines: [String] = []
        if let languagePrompt = configuration.inputLanguage.azureOpenAIRealtimePrompt {
            lines.append(languagePrompt)
        }
        if configuration.inputLanguage == .english,
           let promptDescription = configuration.speakerIdentity?.transcriptionPromptDescription {
            lines.append(
                "The speaker identity is \(promptDescription). "
                    + "Account for accent-influenced English pronunciation when choosing the transcript, "
                    + "but only use a word or spelling when it is supported by the audio "
                    + "and surrounding source-language context."
            )
        }
        lines.append(
            "Transcribe only the speech that was heard. "
                + "Preserve the heard language form when the speaker code-switches. "
                + "Do not add content, polish wording, summarize, or formalize spoken language."
        )

        let phraseHints = configuration.phraseHints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !phraseHints.isEmpty {
            lines.append(
                "Use likely vocabulary as canonical spelling only when the audio sounds like it; "
                    + "preserve Latin spelling and capitalization without translation or localization."
            )
            lines.append("Never output the likely vocabulary list itself as the transcript.")
            lines.append("Likely vocabulary: \(phraseHints.joined(separator: ", ")).")
        }

        return lines.joined(separator: "\n")
    }

    static func isLikelyVocabularyListLeak(_ text: String, phraseHints: [String]) -> Bool {
        let normalizedPhraseHints = phraseHints
            .map(normalizedVocabularyTerm)
            .filter { !$0.isEmpty }

        guard normalizedPhraseHints.count > 1 else {
            return false
        }

        return vocabularyTerms(from: text) == normalizedPhraseHints
    }

    static func vocabularyTerms(from text: String) -> [String] {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedCandidate = candidate.lowercased()
        let prefix = "likely vocabulary:"
        if lowercasedCandidate.hasPrefix(prefix) {
            candidate = String(candidate.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        while let lastScalar = candidate.unicodeScalars.last,
              CharacterSet(charactersIn: ".。").contains(lastScalar) {
            candidate.removeLast()
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return candidate
            .split { character in
                character == "," || character == "，"
            }
            .map { normalizedVocabularyTerm(String($0)) }
            .filter { !$0.isEmpty }
    }

    static func normalizedVocabularyTerm(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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

    static func errorDetail(_ error: Error, phase: String) -> String {
        switch error {
        case let error as AzureOpenAIAudioTranscriptionError:
            "phase=\(phase); \(error.diagnosticDescription)"
        default:
            "phase=\(phase); error=\(error.localizedDescription)"
        }
    }

    static func replacementCharacterCount(in text: String) -> Int {
        text.unicodeScalars.filter { $0.value == 0xFFFD }.count
    }

    static func audioMilliseconds(forPCM16ByteCount byteCount: Int) -> UInt64 {
        let sampleCount = byteCount / Self.bytesPerSample
        return UInt64((Double(sampleCount) / Double(Self.sampleRate) * 1_000).rounded())
    }

    static func byteOffset(forAudioMilliseconds milliseconds: UInt64) -> Int {
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
    nonisolated mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

private extension FixedWidthInteger {
    nonisolated var littleEndianData: Data {
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
            "Transcribe Mandarin in Taiwan Traditional Chinese. Do not output Simplified Chinese. "
                + "Mandarin speech may code-switch into English; preserve the heard language form, "
                + "and do not convert code-switched speech into phonetically similar words in another language."
        case .english:
            "Transcribe English in English. "
                + "English speech may code-switch into Mandarin or Chinese; preserve the heard language form, "
                + "and do not translate code-switched speech into English."
        }
    }
}
