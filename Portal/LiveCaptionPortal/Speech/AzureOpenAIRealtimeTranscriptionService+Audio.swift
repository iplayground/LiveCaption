import Foundation

extension AzureOpenAIRealtimeTranscriptionService {
    func audioSegment(for event: RecognizedCaptionEvent) -> AudioSegment {
        let startMilliseconds = event.offsetTicks / Self.ticksPerMillisecond
        let durationMilliseconds = max(event.durationTicks / Self.ticksPerMillisecond, 1)
        let paddedStartMilliseconds = startMilliseconds > Self.audioPaddingMilliseconds
            ? startMilliseconds - Self.audioPaddingMilliseconds
            : 0
        let paddedEndMilliseconds = min(
            bufferedAudioMilliseconds,
            startMilliseconds + durationMilliseconds + Self.audioPaddingMilliseconds
        )
        return AudioSegment(
            startMilliseconds: startMilliseconds,
            durationMilliseconds: durationMilliseconds,
            paddedStartMilliseconds: paddedStartMilliseconds,
            paddedEndMilliseconds: paddedEndMilliseconds
        )
    }

    func emitSkippedAudioDiagnostic(reason: String, segment: AudioSegment) {
        emitDiagnostic(
            level: .warning,
            detail: [
                "phase=transcriptionSkipped",
                "reason=\(reason)",
                "audioStartMs=\(segment.startMilliseconds)",
                "audioDurationMs=\(segment.durationMilliseconds)",
                "bufferedAudioMs=\(bufferedAudioMilliseconds)",
            ].joined(separator: "; ")
        )
    }

    func safeTranscriptionText(
        _ normalizedText: String,
        configuration: AzureOpenAITranscriptionConfig,
        segment: AudioSegment
    ) -> String {
        guard Self.isLikelyVocabularyListLeak(normalizedText, phraseHints: configuration.phraseHints) else {
            emitTranscriptDiagnostic(
                text: normalizedText,
                audioStartMilliseconds: segment.startMilliseconds,
                audioEndMilliseconds: segment.startMilliseconds + segment.durationMilliseconds
            )
            return normalizedText
        }

        emitPromptVocabularyLeakDiagnostic(
            normalizedText: normalizedText,
            phraseHintCount: configuration.phraseHints.count,
            segment: segment
        )
        return ""
    }

    func emitPromptVocabularyLeakDiagnostic(
        normalizedText: String,
        phraseHintCount: Int,
        segment: AudioSegment
    ) {
        emitDiagnostic(
            level: .warning,
            detail: [
                "phase=transcriptionCompleted",
                "endpoint=audioTranscriptions",
                "issue=promptVocabularyLeak",
                "transcriptChars=\(normalizedText.count)",
                "phraseHintCount=\(phraseHintCount)",
                "audioStartMs=\(segment.startMilliseconds)",
                "audioEndMs=\(segment.startMilliseconds + segment.durationMilliseconds)",
            ].joined(separator: "; ")
        )
    }

    func publishTranscriptionResult(
        openAIText: String,
        speechText: String,
        event: RecognizedCaptionEvent
    ) {
        guard !openAIText.isEmpty || !speechText.isEmpty else {
            return
        }

        onTranscription?(
            AzureOpenAIRealtimeTranscriptionResult(
                captionEventID: event.id,
                openAIText: openAIText,
                speechText: speechText,
                offsetTicks: event.offsetTicks,
                durationTicks: event.durationTicks,
                sessionOffsetTicks: event.sessionOffsetTicks,
                inputLanguage: event.inputLanguage,
                processingGeneration: event.processingGeneration
            )
        )
    }

    func audioSlice(startMilliseconds: UInt64, endMilliseconds: UInt64) -> Data {
        let startByte = Self.byteOffset(forAudioMilliseconds: startMilliseconds)
        let endByte = min(Self.byteOffset(forAudioMilliseconds: endMilliseconds), audioBuffer.count)
        guard startByte < endByte else {
            return Data()
        }

        return audioBuffer.subdata(in: startByte..<endByte)
    }
}
