import Foundation

struct SubtitleExportSession {
    private static let ticksPerSecond: Double = 10_000_000
    private static let minimumCueDuration: TimeInterval = 1.5

    let directoryURL: URL
    let fallbackDirectoryURL: URL
    private let rootDirectoryURL: URL
    private let outputLanguages: [SpeechOutputLanguage]
    private var offsetBaselineTicksByMode: [CaptionQualityMode: UInt64] = [:]
    private var cuesByModeAndLanguageID: [CaptionQualityMode: [String: [SubtitleCue]]]

    init(
        rootDirectoryURL: URL,
        sessionTitle: String,
        startedAt: Date,
        outputLanguages: [SpeechOutputLanguage]
    ) throws {
        let sessionDirectoryName = Self.sessionDirectoryName(sessionTitle: sessionTitle, startedAt: startedAt)
        directoryURL = rootDirectoryURL.appendingPathComponent(sessionDirectoryName, isDirectory: true)
        fallbackDirectoryURL = try Self.fallbackRootDirectoryURL()
            .appendingPathComponent(sessionDirectoryName, isDirectory: true)
        self.rootDirectoryURL = rootDirectoryURL
        self.outputLanguages = outputLanguages
        cuesByModeAndLanguageID = Dictionary(
            uniqueKeysWithValues: CaptionQualityMode.allCases.map { mode in
                (
                    mode,
                    Dictionary(uniqueKeysWithValues: outputLanguages.map { ($0.id, []) })
                )
            }
        )
    }

    mutating func append(
        event: RecognizedCaptionEvent,
        inputLanguage: InputLanguage,
        mode: CaptionQualityMode
    ) {
        guard let captionMode = event.captionModes[mode] else {
            return
        }

        if offsetBaselineTicksByMode[mode] == nil {
            offsetBaselineTicksByMode[mode] = event.offsetTicks
        }

        let startTime = timeInterval(from: event.offsetTicks, mode: mode)
        let duration = Self.timeInterval(fromTicks: event.durationTicks)
        let endTime = startTime + max(duration, Self.minimumCueDuration)

        for language in outputLanguages {
            let text: String?
            if let languageText = captionMode.translations[language.id] {
                text = languageText
            } else if language.id == inputLanguage.matchingOutputLanguageID {
                text = captionMode.text
            } else {
                text = nil
            }

            guard let normalizedText = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !normalizedText.isEmpty
            else {
                continue
            }

            appendCue(
                SubtitleCue(startTime: startTime, endTime: endTime, text: normalizedText),
                mode: mode,
                languageID: language.id
            )
        }
    }

    func writeFiles() throws -> [URL] {
        let didStartAccessing = rootDirectoryURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                rootDirectoryURL.stopAccessingSecurityScopedResource()
            }
        }

        return try writeFiles(to: directoryURL)
    }

    func writeFallbackFiles() throws -> [URL] {
        try writeFiles(to: fallbackDirectoryURL)
    }

    func fallbackFailureDetail(primaryError: Error, fallbackFileURLs: [URL]) -> String {
        let fallbackLocation = fallbackFileURLs.isEmpty
            ? fallbackDirectoryURL.path(percentEncoded: false)
            : fallbackFileURLs.map { $0.path(percentEncoded: false) }.joined(separator: "\n")

        return L10n.text("srt.fallbackDetail", primaryError.localizedDescription, fallbackLocation)
    }

    private func writeFiles(to directoryURL: URL) throws -> [URL] {
        var writtenFileURLs: [URL] = []
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        for mode in CaptionQualityMode.allCases {
            let modeDirectoryURL = directoryURL.appendingPathComponent(mode.rawValue, isDirectory: true)

            for language in outputLanguages {
                let cues = cuesByModeAndLanguageID[mode]?[language.id, default: []] ?? []
                guard !cues.isEmpty else {
                    continue
                }

                try FileManager.default.createDirectory(at: modeDirectoryURL, withIntermediateDirectories: true)
                let fileURL = modeDirectoryURL.appendingPathComponent("\(language.id).srt")
                try Self.renderSRT(cues: cues).write(to: fileURL, atomically: true, encoding: .utf8)
                writtenFileURLs.append(fileURL)
            }
        }

        return writtenFileURLs
    }

    private func timeInterval(from ticks: UInt64, mode: CaptionQualityMode) -> TimeInterval {
        let baseline = offsetBaselineTicksByMode[mode] ?? ticks
        guard ticks >= baseline else {
            return 0
        }

        return Self.timeInterval(fromTicks: ticks - baseline)
    }

    private mutating func appendCue(_ cue: SubtitleCue, mode: CaptionQualityMode, languageID: String) {
        var cues = cuesByModeAndLanguageID[mode, default: [:]][languageID, default: []]
        if mode == .accurate,
           let lastCue = cues.last,
           Self.shouldMergeAccurateCue(lastCue, with: cue) {
            cues[cues.count - 1] = SubtitleCue(
                startTime: lastCue.startTime,
                endTime: max(lastCue.endTime, cue.endTime),
                text: Self.mergedText(lastCue.text, cue.text)
            )
            cuesByModeAndLanguageID[mode, default: [:]][languageID] = cues
            return
        }

        if let lastCue = cues.last, lastCue.endTime > cue.startTime {
            cues[cues.count - 1] = SubtitleCue(
                startTime: lastCue.startTime,
                endTime: cue.startTime,
                text: lastCue.text
            )
        }

        cues.append(cue)
        cuesByModeAndLanguageID[mode, default: [:]][languageID] = cues
    }

    private static func shouldMergeAccurateCue(_ previousCue: SubtitleCue, with nextCue: SubtitleCue) -> Bool {
        let maximumGap: TimeInterval = 0.35
        guard nextCue.startTime - previousCue.endTime <= maximumGap else {
            return false
        }

        return !endsWithSentenceBoundary(previousCue.text)
    }

    private static func endsWithSentenceBoundary(_ value: String) -> Bool {
        guard let lastCharacter = value.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }

        return ".。！？!?".contains(lastCharacter)
    }

    private static func mergedText(_ first: String, _ second: String) -> String {
        let trimmedFirst = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecond = second.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedFirst.isEmpty else {
            return trimmedSecond
        }

        guard !trimmedSecond.isEmpty else {
            return trimmedFirst
        }

        if let firstCharacter = trimmedSecond.first,
           ",.。！？!?、，；;：:)）]」』".contains(firstCharacter) {
            return trimmedFirst + trimmedSecond
        }

        if let lastCharacter = trimmedFirst.last,
           "（([「『".contains(lastCharacter) {
            return trimmedFirst + trimmedSecond
        }

        if containsCJKText(trimmedFirst) || containsCJKText(trimmedSecond) {
            return trimmedFirst + trimmedSecond
        }

        return trimmedFirst + " " + trimmedSecond
    }

    private static func containsCJKText(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)
                || (0x3400...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
    }

    private static func timeInterval(fromTicks ticks: UInt64) -> TimeInterval {
        Double(ticks) / ticksPerSecond
    }

    private static func renderSRT(cues: [SubtitleCue]) -> String {
        cues.enumerated()
            .map { index, cue in
                """
                \(index + 1)
                \(formatTimecode(cue.startTime)) --> \(formatTimecode(cue.endTime))
                \(cue.text)
                """
            }
            .joined(separator: "\n\n")
            + "\n"
    }

    private static func formatTimecode(_ timeInterval: TimeInterval) -> String {
        let milliseconds = Int((max(0, timeInterval) * 1000).rounded())
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds % 3_600_000) / 60_000
        let seconds = (milliseconds % 60_000) / 1000
        let remainingMilliseconds = milliseconds % 1000

        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, remainingMilliseconds)
    }

    private static func sessionDirectoryName(sessionTitle: String, startedAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMdd_HHmm"

        let datePrefix = formatter.string(from: startedAt)
        let sanitizedTitle = sanitizePathComponent(sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines))

        guard !sanitizedTitle.isEmpty else {
            return datePrefix
        }

        return "\(datePrefix) \(sanitizedTitle)"
    }

    private static func fallbackRootDirectoryURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("LiveCaptionPortal", isDirectory: true)
        .appendingPathComponent("SRT Recovery", isDirectory: true)
    }

    private static func sanitizePathComponent(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)

        return value
            .components(separatedBy: invalidCharacters)
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SubtitleCue {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}
