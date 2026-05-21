//
//  ContentView.swift
//  LiveCaptionPortal
//
//  Created by Hao Lee on 2026/4/26.
//

import SwiftUI

struct ContentView: View {
    @State var inputLanguage = InputLanguage.mandarin
    @State var speakerIdentity = SpeakerIdentity.chinese
    @StateObject var audioInputController = AudioInputController()
    @StateObject var speechRecognitionController = SpeechRecognitionController()
    @State var isCaptionSessionActive = false
    @State var captionSessionStatus = CaptionSessionStatus.notStarted
    @State var captionSessionStartedAt: Date?
    @State var captionSessionElapsedTime: TimeInterval = 0
    @State var captionProcessingPhase = CaptionProcessingPhase.opening
    @State var captionProcessingGeneration = 0
    @State var speechSettings: SpeechSettings
    @State var speechAuthorizationStatus: SpeechAuthorizationStatus
    @State var azureOpenAIConnectionStatus: AzureOpenAIConnectionStatus
    @State var shouldVerifySpeechAuthorizationOnLaunch: Bool
    @State var relaySettings: RelaySettings
    @State var relayConnectionStatus: RelayConnectionStatus
    @State var shouldVerifyRelayConnectionOnLaunch: Bool
    @State var relayLastPublishedAt: Date?
    @State var relayViewerAccessCode: String?
    @State var relayCaptionSessionID: String?
    @State var lastPublishedCaptionAvailability: RelayCaptionAvailability?
    @State var portalStatusHeartbeatTask: Task<Void, Never>?
    @State var subtitleFileSettings: SubtitleFileSettings
    @State var subtitleExportSession: SubtitleExportSession?
    @State var recognizedCaptionCount = 0
    @State var relayPublishedCaptionCounts: [CaptionQualityMode: Int] = [:]
    @State var acceptedSpeechCaptionEventIDs: Set<RecognizedCaptionEvent.ID> = []
    @State var processingGenerationBaseOffsetTicks: UInt64 = 0
    @State var lastAcceptedSpeechSessionEndTicks: UInt64 = 0
    @State var sessionTitle = ""
    @State var subtitleFileAccessStatus = SubtitleFileAccessStatus.notConfigured
    @State var isLogDrawerExpanded = false
    @State var selectedLogLevel = LogLevel.all
    @State var logEntries: [LogEntry] = []
    @StateObject var pubSubCaptionReceiver = PubSubCaptionReceiver()
    @State var accurateTranslationService = AzureOpenAIRealtimeTranslationService()
    @State var accurateTranscriptionService = AzureOpenAIRealtimeTranscriptionService()
    @State var sleepPreventionController = SleepPreventionController()
    @State var projectionCaptureWindowPresenter = ProjectionCaptureWindowPresenter()
    @AppStorage("projectionCapture.displayMode")
    var projectionCaptureDisplayMode = ProjectionPreviewDisplayMode.inline.rawValue
    let windowMinimumSize = WindowLayout.minimumSize
    let relayPublishRetryLimit = 3
    let maximumLogEntryCount = 300
    let portalStatusHeartbeatInterval: Duration = .seconds(30)
    static let relaySessionIDFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    init() {
        let speechSettings = SpeechSettings.load()
        let authorizationStatus = SpeechAuthorizationStatus.load(for: speechSettings)
        let azureOpenAIConnectionStatus = AzureOpenAIConnectionStatus.load(for: speechSettings)
        let shouldVerifySpeechAuthorizationOnLaunch = authorizationStatus == .authorized
        let relaySettings = RelaySettings.load()
        let relayConnectionStatus = RelayConnectionStatus.load(for: relaySettings)
        let shouldVerifyRelayConnectionOnLaunch = relayConnectionStatus == .connected
        let subtitleFileSettings = SubtitleFileSettings.load()

        _speechSettings = State(initialValue: speechSettings)
        _speechAuthorizationStatus = State(
            initialValue: shouldVerifySpeechAuthorizationOnLaunch ? .verifying : authorizationStatus
        )
        _azureOpenAIConnectionStatus = State(initialValue: azureOpenAIConnectionStatus)
        _shouldVerifySpeechAuthorizationOnLaunch = State(initialValue: shouldVerifySpeechAuthorizationOnLaunch)
        _relaySettings = State(initialValue: relaySettings)
        _relayConnectionStatus = State(
            initialValue: shouldVerifyRelayConnectionOnLaunch ? .testing : relayConnectionStatus
        )
        _shouldVerifyRelayConnectionOnLaunch = State(initialValue: shouldVerifyRelayConnectionOnLaunch)
        _subtitleFileSettings = State(initialValue: subtitleFileSettings)
    }
}

extension ContentView {
    var filteredLogEntries: [LogEntry] {
        guard selectedLogLevel != .all else {
            return logEntries
        }

        return logEntries.filter { $0.level == selectedLogLevel }
    }

    var usesInlineProjectionCapture: Bool {
        ProjectionPreviewDisplayMode.mode(for: projectionCaptureDisplayMode) == .inline
    }

    func appendLog(level: LogLevel, title: String, detail: String) {
        logEntries.insert(
            LogEntry(time: LogClock.currentTimeString(), level: level, title: title, detail: detail),
            at: 0
        )

        if logEntries.count > maximumLogEntryCount {
            logEntries.removeLast(logEntries.count - maximumLogEntryCount)
        }
    }

    func appendLog(_ log: PortalWorkflowLog) {
        appendLog(level: log.level, title: log.title, detail: log.detail)
    }

    static func relaySessionID(for date: Date) -> String {
        relaySessionIDFormatter.string(from: date)
            .replacingOccurrences(of: "Z", with: "")
    }

    @MainActor
    func verifySpeechAuthorizationOnLaunchIfNeeded() async {
        guard shouldVerifySpeechAuthorizationOnLaunch else {
            return
        }

        shouldVerifySpeechAuthorizationOnLaunch = false
        let result = await PortalLaunchVerifier.verifySpeechAuthorization(settings: speechSettings)
        speechAuthorizationStatus = result.status
        speechAuthorizationStatus.save()
        appendLog(result.log)
    }

    @MainActor
    func verifyRelayConnectionOnLaunchIfNeeded() async {
        guard shouldVerifyRelayConnectionOnLaunch else {
            return
        }

        shouldVerifyRelayConnectionOnLaunch = false
        let result = await PortalLaunchVerifier.verifyRelayConnection(
            relaySettings: relaySettings,
            speechKey: speechSettings.speechKey
        )
        relayConnectionStatus = result.status
        relayViewerAccessCode = result.connectionTestResult?.viewerAccessCode
        relayConnectionStatus.save()
        appendLog(result.log)
    }

    var body: some View {
        ContentViewLayout(
            audioInputController: audioInputController,
            captionPreviewState: speechRecognitionController.captionPreviewState,
            sessionTitle: $sessionTitle,
            inputLanguage: $inputLanguage,
            speakerIdentity: $speakerIdentity,
            processingInputLanguage: isCaptionSessionActive ? currentProcessingInputLanguage : inputLanguage,
            subtitleFileSettings: $subtitleFileSettings,
            subtitleFileAccessStatus: $subtitleFileAccessStatus,
            speechSettings: $speechSettings,
            speechAuthorizationStatus: $speechAuthorizationStatus,
            azureOpenAIConnectionStatus: $azureOpenAIConnectionStatus,
            relaySettings: $relaySettings,
            relayConnectionStatus: $relayConnectionStatus,
            isLogDrawerExpanded: $isLogDrawerExpanded,
            selectedLogLevel: $selectedLogLevel,
            isCaptionSessionActive: isCaptionSessionActive,
            captionSessionStatus: captionSessionStatus,
            captionSessionStartedAt: captionSessionStartedAt,
            captionSessionElapsedTime: captionSessionElapsedTime,
            captionProcessingPhase: captionProcessingPhase,
            canToggleCaptionSession: canToggleCaptionSession,
            canEnterSpeakerCaptionMode: canEnterSpeakerCaptionMode,
            captionSessionDisabledReason: captionSessionDisabledReason,
            usesInlineProjectionCapture: usesInlineProjectionCapture,
            relayPublishedCaptionCounts: relayPublishedCaptionCounts,
            relayLastPublishedAt: relayLastPublishedAt,
            pubSubCaptionReceiver: pubSubCaptionReceiver,
            logEntries: logEntries,
            filteredLogEntries: filteredLogEntries,
            onToggleCaptionSession: toggleCaptionSession,
            onEnterSpeakerCaptionMode: enterSpeakerCaptionMode,
            onRelayConnectionTested: handleRelayConnectionTested
        ) { level, title, detail in
            appendLog(level: level, title: title, detail: detail)
        }
            .frame(minWidth: windowMinimumSize.width, minHeight: windowMinimumSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .background(KeyboardEventBlocker(isEnabled: captionSessionStatus.blocksKeyboardEvents))
            .background(
                WindowFrameRestorationBridge(
                    storageKey: "portal.mainWindow",
                    minimumSize: windowMinimumSize
                )
            )
            .task {
                audioInputController.activate()
                await verifySpeechAuthorizationOnLaunchIfNeeded()
                await verifyRelayConnectionOnLaunchIfNeeded()
                publishPortalStatusToRelay("online")
                publishCaptionAvailabilityToRelayIfNeeded()
            }
            .onAppear {
                configureAudioCallbacks()
                configureSpeechCallbacks()
                refreshPortalStatusHeartbeat()
                refreshProjectionCaptureWindow()
            }
            .onDisappear {
                projectionCaptureWindowPresenter.close()
                handleDisappear()
                NSApp.terminate(nil)
            }
            .onChange(of: isCaptionSessionActive) {
                updateSpeechRecognition()
                refreshPortalStatusHeartbeat()
            }
            .onChange(of: captionSessionStatus) {
                refreshProjectionCaptureWindow()
            }
            .onChange(of: captionProcessingPhase) {
                refreshProjectionCaptureWindow()
            }
            .onChange(of: audioInputController.isCapturing) {
                handleAudioCaptureStateChange()
            }
            .onChange(of: audioInputController.selectedDeviceID) {
                updateSpeechRecognition()
            }
            .onChange(of: inputLanguage) {
                speechRecognitionController.captionPreviewState.clearLivePreviewAfterInputLanguageChange()
                refreshProjectionCaptureWindow()
                if captionProcessingPhase == .speaker {
                    updateSpeechRecognition()
                }
            }
            .onChange(of: speechSettings) {
                refreshProjectionCaptureWindow()
                updateSpeechRecognition()
                publishCaptionAvailabilityToRelayIfNeeded()
            }
            .onChange(of: azureOpenAIConnectionStatus) {
                updateSpeechRecognition()
                refreshCaptionSessionReadiness()
                publishCaptionAvailabilityToRelayIfNeeded()
            }
            .onChange(of: projectionCaptureDisplayMode) {
                refreshProjectionCaptureWindow()
            }
            .onChange(of: speechAuthorizationStatus) {
                updateSpeechRecognition()
                refreshCaptionSessionReadiness()
            }
            .onChange(of: subtitleFileAccessStatus) {
                refreshCaptionSessionReadiness()
            }
            .onChange(of: relayConnectionStatus) {
                refreshCaptionSessionReadiness()
                refreshPortalStatusHeartbeat()
            }
            .onChange(of: relaySettings) {
                relayLastPublishedAt = nil
                relayViewerAccessCode = nil
                relayCaptionSessionID = nil
                lastPublishedCaptionAvailability = nil
                relayPublishedCaptionCounts.removeAll()
                pubSubCaptionReceiver.disconnect()
                refreshPortalStatusHeartbeat()
            }
            .focusedSceneValue(
                \.portalEnvironmentTransferActions,
                 PortalEnvironmentTransferActions(
                    canImport: !isCaptionSessionActive,
                    importSettings: importPortalEnvironmentSettings,
                    exportSettings: exportPortalEnvironmentSettings
                 )
            )
    }
}
