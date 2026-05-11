import SwiftUI

struct ContentViewLayout: View {
    @ObservedObject var audioInputController: AudioInputController
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    @Binding var sessionTitle: String
    @Binding var inputLanguage: InputLanguage
    @Binding var subtitleFileSettings: SubtitleFileSettings
    @Binding var subtitleFileAccessStatus: SubtitleFileAccessStatus
    @Binding var speechSettings: SpeechSettings
    @Binding var speechAuthorizationStatus: SpeechAuthorizationStatus
    @Binding var relaySettings: RelaySettings
    @Binding var relayConnectionStatus: RelayConnectionStatus
    @Binding var isLogDrawerExpanded: Bool
    @Binding var selectedLogLevel: LogLevel
    let isCaptionSessionActive: Bool
    let captionSessionStatus: CaptionSessionStatus
    let captionSessionStartedAt: Date?
    let captionSessionElapsedTime: TimeInterval
    let canToggleCaptionSession: Bool
    let captionSessionDisabledReason: String?
    let usesInlineProjectionCapture: Bool
    let recognizedCaptionCount: Int
    let relayLastPublishedAt: Date?
    let logEntries: [LogEntry]
    let filteredLogEntries: [LogEntry]
    let onToggleCaptionSession: () -> Void
    let onLogEvent: (LogLevel, String, String) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header

                Divider()

                if usesInlineProjectionCapture {
                    projectionCapture

                    Divider()
                }

                workspaceColumns
            }
            .padding(.bottom, WindowLayout.logDrawerHeaderHeight)

            logDrawer
        }
    }

    private var header: some View {
        HeaderView(
            isCaptionSessionActive: isCaptionSessionActive,
            captionSessionStartedAt: captionSessionStartedAt,
            captionSessionElapsedTime: captionSessionElapsedTime,
            canToggleCaptionSession: canToggleCaptionSession,
            captionSessionDisabledReason: captionSessionDisabledReason,
            onToggleCaptionSession: onToggleCaptionSession
        )
    }

    private var projectionCapture: some View {
        ProjectionCaptureSection(
            inputLanguage: inputLanguage,
            outputLanguages: speechSettings.selectedOutputLanguages,
            captionPreviewState: captionPreviewState
        )
    }

    private var workspaceColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            ControlSidebar(
                audioInputController: audioInputController,
                subtitleFileSettings: $subtitleFileSettings,
                subtitleFileAccessStatus: $subtitleFileAccessStatus,
                captionSessionStatus: captionSessionStatus,
                areConfigurationControlsLocked: captionSessionStatus.locksConfigurationControls,
                speechAuthorizationStatus: speechAuthorizationStatus,
                relayConnectionStatus: relayConnectionStatus,
                onLogEvent: onLogEvent
            )

            Divider()

            CaptionWorkspace(
                sessionTitle: $sessionTitle,
                inputLanguage: $inputLanguage,
                areConfigurationControlsLocked: captionSessionStatus.locksConfigurationControls,
                outputLanguages: speechSettings.selectedOutputLanguages,
                captionPreviewState: captionPreviewState
            )

            Divider()

            StatusSidebar(
                inputLanguage: inputLanguage,
                captionSessionStatus: captionSessionStatus,
                areConfigurationControlsLocked: captionSessionStatus.locksConfigurationControls,
                speechSettings: $speechSettings,
                captionPreviewState: captionPreviewState,
                speechAuthorizationStatus: $speechAuthorizationStatus,
                relaySettings: $relaySettings,
                relayConnectionStatus: $relayConnectionStatus,
                recognizedCaptionCount: recognizedCaptionCount,
                relayLastPublishedAt: relayLastPublishedAt,
                logEntries: logEntries,
                onLogEvent: onLogEvent
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var logDrawer: some View {
        LogDrawer(
            isExpanded: $isLogDrawerExpanded,
            selectedLevel: $selectedLogLevel,
            entries: filteredLogEntries
        )
        .zIndex(100)
    }
}
