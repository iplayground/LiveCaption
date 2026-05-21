import SwiftUI

extension ContentView {
    func appendCaptionToSubtitleExportSession(_ event: RecognizedCaptionEvent, mode: CaptionQualityMode) {
        guard var subtitleExportSession else {
            return
        }

        subtitleExportSession.append(event: event, inputLanguage: event.inputLanguage, mode: mode)
        self.subtitleExportSession = subtitleExportSession
    }

    func finishSubtitleExportSession() {
        guard let subtitleExportSession else {
            if captionSessionStatus == .stopping {
                captionSessionStatus = .completed
            }
            sleepPreventionController.stopPreventingSleep()
            return
        }

        do {
            let writtenFileURLs = try subtitleExportSession.writeFiles()
            let detail = writtenFileURLs.isEmpty
                ? L10n.text("srt.noCaptionEvents")
                : L10n.text(
                    "srt.outputSummary",
                    writtenFileURLs.count,
                    subtitleExportSession.directoryURL.path(percentEncoded: false)
                )
            appendLog(level: .info, title: L10n.text("log.srt.outputCompleted"), detail: detail)
            captionSessionStatus = .completed
        } catch {
            writeFallbackSubtitleFiles(for: subtitleExportSession, primaryError: error)
        }

        self.subtitleExportSession = nil
        sleepPreventionController.stopPreventingSleep()
    }

    func writeFallbackSubtitleFiles(
        for subtitleExportSession: SubtitleExportSession,
        primaryError: Error
    ) {
        do {
            let writtenFileURLs = try subtitleExportSession.writeFallbackFiles()
            let detail = subtitleExportSession.fallbackFailureDetail(
                primaryError: primaryError,
                fallbackFileURLs: writtenFileURLs
            )
            appendLog(level: .warning, title: L10n.text("log.srt.outputSavedToFallback"), detail: detail)
            captionSessionStatus = .completedWithWarning
        } catch {
            appendLog(
                level: .error,
                title: L10n.text("log.srt.outputFailed"),
                detail: L10n.text("srt.fallbackFailed", primaryError.localizedDescription, error.localizedDescription)
            )
            captionSessionStatus = .failed
        }
    }
}

struct RelayCaptionAvailability: Equatable {
    let sessionID: String?
    let captionModeIDs: [String]
    let languageIDs: [String]

    init(
        sessionID: String?,
        captionModes: [CaptionQualityMode],
        languages: [SpeechOutputLanguage]
    ) {
        self.sessionID = sessionID
        captionModeIDs = captionModes.map(\.rawValue)
        languageIDs = languages.map(\.id)
    }
}

extension AzureOpenAITranscriptionDiagnostic.Level {
    var logLevel: LogLevel {
        switch self {
        case .info:
            .info
        case .warning:
            .warning
        case .error:
            .error
        }
    }
}

extension AzureOpenAIRealtimeTranslationDiagnostic.Level {
    var logLevel: LogLevel {
        switch self {
        case .warning:
            .warning
        case .error:
            .error
        }
    }
}
