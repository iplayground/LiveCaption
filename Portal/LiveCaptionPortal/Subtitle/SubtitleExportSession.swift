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
            offsetBaselineTicksByMode[mode] = event.sessionOffsetTicks
        }

        let startTime = timeInterval(from: event.sessionOffsetTicks, mode: mode)
        let duration = Self.timeInterval(fromTicks: event.durationTicks)
        let endTime = startTime + max(duration, Self.minimumCueDuration)

        var cuesByLanguageID: [String: SubtitleCue] = [:]
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

            cuesByLanguageID[language.id] = SubtitleCue(
                startTime: startTime,
                endTime: endTime,
                text: normalizedText
            )
        }

        if mode == .accurate {
            appendAccurateCues(cuesByLanguageID)
            return
        }

        for (languageID, cue) in cuesByLanguageID {
            appendCue(cue, mode: mode, languageID: languageID)
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

        cues.append(cue)
        cuesByModeAndLanguageID[mode, default: [:]][languageID] = cues
    }

    private mutating func appendAccurateCues(_ cuesByLanguageID: [String: SubtitleCue]) {
        for (languageID, cue) in cuesByLanguageID {
            appendCue(cue, mode: .accurate, languageID: languageID)
        }
    }

    private static func timeInterval(fromTicks ticks: UInt64) -> TimeInterval {
        Double(ticks) / ticksPerSecond
    }

    private static func renderSRT(cues: [SubtitleCue]) -> String {
        normalizedCues(cues).enumerated()
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

    private static func normalizedCues(_ cues: [SubtitleCue]) -> [SubtitleCue] {
        let sortedCues = cues.sorted {
            if $0.startTime == $1.startTime {
                return $0.endTime < $1.endTime
            }

            return $0.startTime < $1.startTime
        }

        var normalized: [SubtitleCue] = []
        for cue in sortedCues {
            if let lastCue = normalized.last, lastCue.endTime > cue.startTime {
                normalized[normalized.count - 1] = SubtitleCue(
                    startTime: lastCue.startTime,
                    endTime: cue.startTime,
                    text: lastCue.text
                )
            }

            normalized.append(cue)
        }

        return normalized
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
