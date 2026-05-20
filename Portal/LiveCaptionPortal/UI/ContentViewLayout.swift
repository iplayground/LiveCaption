import SwiftUI

enum CaptionProcessingPhase: Equatable {
    case opening
    case transitioningToSpeaker
    case speaker

    var title: String {
        switch self {
        case .opening:
            L10n.text("caption.processingPhase.opening")
        case .transitioningToSpeaker:
            L10n.text("caption.processingPhase.transitioning")
        case .speaker:
            L10n.text("caption.processingPhase.speaker")
        }
    }
}

struct ContentViewLayout: View {
    @State private var logDrawerContentHeight = WindowLayout.defaultLogDrawerContentHeight
    @ObservedObject var audioInputController: AudioInputController
    @ObservedObject var captionPreviewState: SpeechCaptionPreviewState
    @Binding var sessionTitle: String
    @Binding var inputLanguage: InputLanguage
    let processingInputLanguage: InputLanguage
    @Binding var subtitleFileSettings: SubtitleFileSettings
    @Binding var subtitleFileAccessStatus: SubtitleFileAccessStatus
    @Binding var speechSettings: SpeechSettings
    @Binding var speechAuthorizationStatus: SpeechAuthorizationStatus
    @Binding var azureOpenAIConnectionStatus: AzureOpenAIConnectionStatus
    @Binding var relaySettings: RelaySettings
    @Binding var relayConnectionStatus: RelayConnectionStatus
    @Binding var isLogDrawerExpanded: Bool
    @Binding var selectedLogLevel: LogLevel
    let isCaptionSessionActive: Bool
    let captionSessionStatus: CaptionSessionStatus
    let captionSessionStartedAt: Date?
    let captionSessionElapsedTime: TimeInterval
    let captionProcessingPhase: CaptionProcessingPhase
    let canToggleCaptionSession: Bool
    let canEnterSpeakerCaptionMode: Bool
    let captionSessionDisabledReason: String?
    let usesInlineProjectionCapture: Bool
    let relayPublishedCaptionCounts: [CaptionQualityMode: Int]
    let relayLastPublishedAt: Date?
    @ObservedObject var pubSubCaptionReceiver: PubSubCaptionReceiver
    let logEntries: [LogEntry]
    let filteredLogEntries: [LogEntry]
    let onToggleCaptionSession: () -> Void
    let onEnterSpeakerCaptionMode: () -> Void
    let onRelayConnectionTested: (RelayConnectionTestResult) -> Void
    let onLogEvent: (LogLevel, String, String) -> Void

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header

                Divider()

                if usesInlineProjectionCapture {
                    projectionCapture

                    Divider()
                }

                workspaceColumns
                logDrawer(windowHeight: geometry.size.height)
            }
        }
    }

    private var header: some View {
        HeaderView(
            isCaptionSessionActive: isCaptionSessionActive,
            captionSessionStartedAt: captionSessionStartedAt,
            captionSessionElapsedTime: captionSessionElapsedTime,
            captionProcessingPhase: captionProcessingPhase,
            canToggleCaptionSession: canToggleCaptionSession,
            canEnterSpeakerCaptionMode: canEnterSpeakerCaptionMode,
            captionSessionDisabledReason: captionSessionDisabledReason,
            onToggleCaptionSession: onToggleCaptionSession,
            onEnterSpeakerCaptionMode: onEnterSpeakerCaptionMode
        )
    }

    private var projectionCapture: some View {
        ProjectionCaptureSection(
            inputLanguage: processingInputLanguage,
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
                azureOpenAIConnectionStatus: azureOpenAIConnectionStatus,
                relayConnectionStatus: relayConnectionStatus,
                onLogEvent: onLogEvent
            )

            Divider()

            CaptionWorkspace(
                sessionTitle: $sessionTitle,
                inputLanguage: $inputLanguage,
                processingInputLanguage: processingInputLanguage,
                areConfigurationControlsLocked: captionSessionStatus.locksConfigurationControls,
                outputLanguages: speechSettings.portalVisibleOutputLanguages,
                captionPreviewState: captionPreviewState,
                pubSubCaptionReceiver: pubSubCaptionReceiver
            )

            Divider()

            StatusSidebar(
                inputLanguage: inputLanguage,
                captionSessionStatus: captionSessionStatus,
                areConfigurationControlsLocked: captionSessionStatus.locksConfigurationControls,
                speechSettings: $speechSettings,
                captionPreviewState: captionPreviewState,
                speechAuthorizationStatus: $speechAuthorizationStatus,
                azureOpenAIConnectionStatus: $azureOpenAIConnectionStatus,
                relaySettings: $relaySettings,
                relayConnectionStatus: $relayConnectionStatus,
                relayPublishedCaptionCounts: relayPublishedCaptionCounts,
                relayLastPublishedAt: relayLastPublishedAt,
                logEntries: logEntries,
                onLogEvent: onLogEvent,
                onRelayConnectionTested: onRelayConnectionTested
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func logDrawer(windowHeight: CGFloat) -> some View {
        LogDrawer(
            isExpanded: $isLogDrawerExpanded,
            selectedLevel: $selectedLogLevel,
            contentHeight: $logDrawerContentHeight,
            maximumContentHeight: maximumLogDrawerContentHeight(for: windowHeight),
            entries: filteredLogEntries
        )
    }

    private func maximumLogDrawerContentHeight(for windowHeight: CGFloat) -> CGFloat {
        max(
            WindowLayout.defaultLogDrawerContentHeight,
            (windowHeight / 2) - WindowLayout.logDrawerHeaderHeight
        )
    }
}
