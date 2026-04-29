import Foundation

struct SubtitleExportSession {
    private static let ticksPerSecond: Double = 10_000_000
    private static let minimumCueDuration: TimeInterval = 1.5

    let directoryURL: URL
    let fallbackDirectoryURL: URL
    private let rootDirectoryURL: URL
    private let outputLanguages: [SpeechOutputLanguage]
    private var offsetBaselineTicks: UInt64?
    private var cuesByLanguageID: [String: [SubtitleCue]]

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
        cuesByLanguageID = Dictionary(uniqueKeysWithValues: outputLanguages.map { ($0.id, []) })
    }

    mutating func append(event: RecognizedCaptionEvent, inputLanguage: InputLanguage) {
        if offsetBaselineTicks == nil {
            offsetBaselineTicks = event.offsetTicks
        }

        let startTime = timeInterval(from: event.offsetTicks)
        let duration = Self.timeInterval(fromTicks: event.durationTicks)
        let endTime = startTime + max(duration, Self.minimumCueDuration)

        for language in outputLanguages {
            let text: String?
            if language.id == inputLanguage.matchingOutputLanguageID {
                text = event.text
            } else {
                text = event.translations[language.id]
            }

            guard let normalizedText = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !normalizedText.isEmpty
            else {
                continue
            }

            cuesByLanguageID[language.id, default: []].append(
                SubtitleCue(startTime: startTime, endTime: endTime, text: normalizedText)
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

    private func writeFiles(to directoryURL: URL) throws -> [URL] {
        var writtenFileURLs: [URL] = []
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        for language in outputLanguages {
            let cues = cuesByLanguageID[language.id, default: []]
            guard !cues.isEmpty else {
                continue
            }

            let fileURL = directoryURL.appendingPathComponent("\(language.id).srt")
            try Self.renderSRT(cues: cues).write(to: fileURL, atomically: true, encoding: .utf8)
            writtenFileURLs.append(fileURL)
        }

        return writtenFileURLs
    }

    private func timeInterval(from ticks: UInt64) -> TimeInterval {
        let baseline = offsetBaselineTicks ?? ticks
        guard ticks >= baseline else {
            return 0
        }

        return Self.timeInterval(fromTicks: ticks - baseline)
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
