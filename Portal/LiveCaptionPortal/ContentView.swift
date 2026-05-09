//
//  ContentView.swift
//  LiveCaptionPortal
//
//  Created by Hao Lee on 2026/4/26.
//

import SwiftUI
import IOKit.pwr_mgt

struct ContentView: View {
    @State private var inputLanguage = InputLanguage.mandarin
    @StateObject private var audioInputController = AudioInputController()
    @StateObject private var speechRecognitionController = SpeechRecognitionController()
    @State private var isCaptionSessionActive = false
    @State private var captionSessionStatus = CaptionSessionStatus.notStarted
    @State private var captionSessionStartedAt: Date?
    @State private var captionSessionElapsedTime: TimeInterval = 0
    @State private var speechSettings: SpeechSettings
    @State private var speechAuthorizationStatus: SpeechAuthorizationStatus
    @State private var shouldVerifySpeechAuthorizationOnLaunch: Bool
    @State private var relaySettings: RelaySettings
    @State private var relayConnectionStatus: RelayConnectionStatus
    @State private var shouldVerifyRelayConnectionOnLaunch: Bool
    @State private var relayLastPublishedAt: Date?
    @State private var subtitleFileSettings: SubtitleFileSettings
    @State private var subtitleExportSession: SubtitleExportSession?
    @State private var recognizedCaptionCount = 0
    @State private var sessionTitle = ""
    @State private var subtitleFileAccessStatus = SubtitleFileAccessStatus.notConfigured
    @State private var isLogDrawerExpanded = false
    @State private var selectedLogLevel = LogLevel.all
    @State private var logEntries: [LogEntry] = []
    @State private var sleepPreventionController = SleepPreventionController()
    private let windowMinimumSize = WindowLayout.minimumSize
    private let relayPublishRetryLimit = 3
    private let maximumLogEntryCount = 300

    init() {
        let speechSettings = SpeechSettings.load()
        let authorizationStatus = SpeechAuthorizationStatus.load(for: speechSettings)
        let shouldVerifySpeechAuthorizationOnLaunch = authorizationStatus == .authorized
        let relaySettings = RelaySettings.load()
        let relayConnectionStatus = RelayConnectionStatus.load(for: relaySettings)
        let shouldVerifyRelayConnectionOnLaunch = relayConnectionStatus == .connected
        let subtitleFileSettings = SubtitleFileSettings.load()

        _speechSettings = State(initialValue: speechSettings)
        _speechAuthorizationStatus = State(
            initialValue: shouldVerifySpeechAuthorizationOnLaunch ? .verifying : authorizationStatus
        )
        _shouldVerifySpeechAuthorizationOnLaunch = State(initialValue: shouldVerifySpeechAuthorizationOnLaunch)
        _relaySettings = State(initialValue: relaySettings)
        _relayConnectionStatus = State(
            initialValue: shouldVerifyRelayConnectionOnLaunch ? .testing : relayConnectionStatus
        )
        _shouldVerifyRelayConnectionOnLaunch = State(initialValue: shouldVerifyRelayConnectionOnLaunch)
        _subtitleFileSettings = State(initialValue: subtitleFileSettings)
    }

    private var filteredLogEntries: [LogEntry] {
        guard selectedLogLevel != .all else {
            return logEntries
        }

        return logEntries.filter { $0.level == selectedLogLevel }
    }

    private func appendLog(level: LogLevel, title: String, detail: String) {
        logEntries.insert(
            LogEntry(time: LogClock.currentTimeString(), level: level, title: title, detail: detail),
            at: 0
        )

        if logEntries.count > maximumLogEntryCount {
            logEntries.removeLast(logEntries.count - maximumLogEntryCount)
        }
    }

    @MainActor
    private func verifySpeechAuthorizationOnLaunchIfNeeded() async {
        guard shouldVerifySpeechAuthorizationOnLaunch else {
            return
        }

        shouldVerifySpeechAuthorizationOnLaunch = false
        let settingsToTest = speechSettings

        do {
            let result = try await settingsToTest.testConnection()
            speechAuthorizationStatus = .authorized
            speechAuthorizationStatus.save()
            appendLog(level: .info, title: L10n.text("log.speech.reauthorizationSucceeded"), detail: "Region \(result.region)")
        } catch {
            let message = error.localizedDescription
            speechAuthorizationStatus = .failed
            speechAuthorizationStatus.save()
            appendLog(level: .error, title: L10n.text("log.speech.reauthorizationFailed"), detail: message)
        }
    }

    @MainActor
    private func verifyRelayConnectionOnLaunchIfNeeded() async {
        guard shouldVerifyRelayConnectionOnLaunch else {
            return
        }

        shouldVerifyRelayConnectionOnLaunch = false
        let settingsToTest = relaySettings
        let speechKey = speechSettings.speechKey

        do {
            let result = try await settingsToTest.testConnection(speechKey: speechKey)
            relayConnectionStatus = .connected
            relayConnectionStatus.save()
            appendLog(
                level: .info,
                title: L10n.text("log.relay.connectionTestSucceeded"),
                detail: result.logDetail
            )
        } catch {
            let message = error.localizedDescription
            relayConnectionStatus = .failed
            relayConnectionStatus.save()
            appendLog(level: .error, title: L10n.text("log.relay.connectionTestFailed"), detail: message)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HeaderView(
                    isCaptionSessionActive: isCaptionSessionActive,
                    captionSessionStartedAt: captionSessionStartedAt,
                    captionSessionElapsedTime: captionSessionElapsedTime,
                    canToggleCaptionSession: canToggleCaptionSession,
                    captionSessionDisabledReason: captionSessionDisabledReason,
                    onToggleCaptionSession: toggleCaptionSession
                )

                Divider()

                ProjectionCaptureSection(
                    inputLanguage: inputLanguage,
                    outputLanguages: speechSettings.selectedOutputLanguages,
                    captionPreviewState: speechRecognitionController.captionPreviewState
                )

                Divider()

                HStack(alignment: .top, spacing: 0) {
                    ControlSidebar(
                        audioInputController: audioInputController,
                        subtitleFileSettings: $subtitleFileSettings,
                        subtitleFileAccessStatus: $subtitleFileAccessStatus,
                        captionSessionStatus: captionSessionStatus,
                        areConfigurationControlsLocked: captionSessionStatus.locksConfigurationControls,
                        speechAuthorizationStatus: speechAuthorizationStatus,
                        relayConnectionStatus: relayConnectionStatus
                    ) { level, title, detail in
                        appendLog(level: level, title: title, detail: detail)
                    }

                    Divider()

                    CaptionWorkspace(
                        sessionTitle: $sessionTitle,
                        inputLanguage: $inputLanguage,
                        areConfigurationControlsLocked: captionSessionStatus.locksConfigurationControls,
                        outputLanguages: speechSettings.selectedOutputLanguages,
                        captionPreviewState: speechRecognitionController.captionPreviewState
                    )

                    Divider()

                    StatusSidebar(
                        inputLanguage: inputLanguage,
                        captionSessionStatus: captionSessionStatus,
                        areConfigurationControlsLocked: captionSessionStatus.locksConfigurationControls,
                        speechSettings: $speechSettings,
                        captionPreviewState: speechRecognitionController.captionPreviewState,
                        speechAuthorizationStatus: $speechAuthorizationStatus,
                        relaySettings: $relaySettings,
                        relayConnectionStatus: $relayConnectionStatus,
                        recognizedCaptionCount: recognizedCaptionCount,
                        relayLastPublishedAt: relayLastPublishedAt,
                        logEntries: logEntries
                    ) { level, title, detail in
                        appendLog(level: level, title: title, detail: detail)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.bottom, WindowLayout.logDrawerHeaderHeight)

            LogDrawer(
                isExpanded: $isLogDrawerExpanded,
                selectedLevel: $selectedLogLevel,
                entries: filteredLogEntries
            )
            .zIndex(100)
        }
        .frame(minWidth: windowMinimumSize.width, minHeight: windowMinimumSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(KeyboardEventBlocker(isEnabled: captionSessionStatus.blocksKeyboardEvents))
        .task {
            audioInputController.activate()
            await verifySpeechAuthorizationOnLaunchIfNeeded()
            await verifyRelayConnectionOnLaunchIfNeeded()
        }
        .onAppear {
            configureSpeechCallbacks()
        }
        .onDisappear {
            finishCaptionSessionTiming()
            finishSubtitleExportSession()
            sleepPreventionController.stopPreventingSleep()
            audioInputController.stopCapture()
            speechRecognitionController.stopRecognition()
        }
        .onChange(of: isCaptionSessionActive) {
            updateSpeechRecognition()
        }
        .onChange(of: audioInputController.isCapturing) {
            if !audioInputController.isCapturing {
                if isCaptionSessionActive {
                    captionSessionStatus = .stopping
                }
                finishCaptionSessionTiming()
                finishSubtitleExportSession()
                isCaptionSessionActive = false
            } else {
                updateSpeechRecognition()
            }

            refreshCaptionSessionReadiness()
        }
        .onChange(of: audioInputController.selectedDeviceID) {
            updateSpeechRecognition()
        }
        .onChange(of: inputLanguage) {
            speechRecognitionController.captionPreviewState.clearLivePreviewAfterInputLanguageChange()
            updateSpeechRecognition()
        }
        .onChange(of: speechSettings) {
            updateSpeechRecognition()
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
        }
        .onChange(of: relaySettings) {
            relayLastPublishedAt = nil
        }
    }

    private var canToggleCaptionSession: Bool {
        if isCaptionSessionActive {
            return true
        }

        return canStartCaptionSession
    }

    private var canStartCaptionSession: Bool {
        audioInputController.isCapturing
            && speechAuthorizationStatus == .authorized
            && subtitleFileAccessStatus == .authorized
            && relayConnectionStatus == .connected
    }

    private var captionSessionDisabledReason: String? {
        if !audioInputController.isCapturing {
            return L10n.text("caption.disabled.enableCaptureFirst")
        }

        if speechAuthorizationStatus != .authorized {
            return L10n.text("caption.disabled.verifySpeechFirst")
        }

        if subtitleFileAccessStatus != .authorized {
            return L10n.text("caption.disabled.configureSubtitleStorageFirst")
        }

        if relayConnectionStatus != .connected {
            return L10n.text("caption.disabled.verifyRelayFirst")
        }

        return nil
    }

    private func updateSpeechRecognition() {
        guard isCaptionSessionActive else {
            speechRecognitionController.stopRecognition(keepsCurrentTranscript: true)
            return
        }

        guard audioInputController.isCapturing else {
            speechRecognitionController.stopRecognition(keepsCurrentTranscript: true)
            return
        }

        speechRecognitionController.startRecognition(
            settings: speechSettings,
            inputLanguage: inputLanguage,
            audioDeviceID: audioInputController.selectedDeviceID,
            authorizationStatus: speechAuthorizationStatus
        )
    }

    private func refreshCaptionSessionReadiness() {
        guard !isCaptionSessionActive else {
            return
        }

        guard canStartCaptionSession else {
            captionSessionStatus = .notStarted
            return
        }

        switch captionSessionStatus {
        case .notStarted, .ready:
            captionSessionStatus = .ready
        case .captioning, .stopping, .completed, .completedWithWarning, .failed:
            break
        }
    }

    private func toggleCaptionSession() {
        if isCaptionSessionActive {
            captionSessionStatus = .stopping
            isCaptionSessionActive = false
            finishCaptionSessionTiming()
            finishSubtitleExportSession()
            sleepPreventionController.stopPreventingSleep()
        } else {
            captionSessionElapsedTime = 0
            relayLastPublishedAt = nil
            recognizedCaptionCount = 0
            speechRecognitionController.resetCaptionSessionMetrics()
            let startedAt = Date()
            captionSessionStartedAt = startedAt

            if beginSubtitleExportSession(startedAt: startedAt) {
                sleepPreventionController.startPreventingSleep()
                captionSessionStatus = .captioning
                isCaptionSessionActive = true
            } else {
                finishCaptionSessionTiming()
                sleepPreventionController.stopPreventingSleep()
                captionSessionStatus = .failed
            }
        }
    }

    private func finishCaptionSessionTiming() {
        guard let captionSessionStartedAt else {
            return
        }

        captionSessionElapsedTime = max(0, Date().timeIntervalSince(captionSessionStartedAt))
        self.captionSessionStartedAt = nil
    }

    private func beginSubtitleExportSession(startedAt: Date) -> Bool {
        guard let storageDirectoryURL = subtitleFileSettings.storageDirectoryURL else {
            subtitleExportSession = nil
            appendLog(
                level: .warning,
                title: L10n.text("log.srt.outputNotCreated"),
                detail: L10n.text("subtitle.storage.notConfigured")
            )
            return false
        }

        do {
            subtitleExportSession = try SubtitleExportSession(
                rootDirectoryURL: storageDirectoryURL,
                sessionTitle: sessionTitle,
                startedAt: startedAt,
                outputLanguages: speechSettings.selectedOutputLanguages
            )
            appendLog(
                level: .info,
                title: L10n.text("log.srt.outputPrepared"),
                detail: subtitleExportSession?.directoryURL.path(percentEncoded: false) ?? ""
            )
            return true
        } catch {
            subtitleExportSession = nil
            appendLog(level: .error, title: L10n.text("log.srt.createFolderFailed"), detail: error.localizedDescription)
            return false
        }
    }

    private func configureSpeechCallbacks() {
        speechRecognitionController.onCaptionCountChanged = { count in
            recognizedCaptionCount = count
        }

        speechRecognitionController.onCaptionEvent = { event in
            handleCaptionEvent(event)
        }
    }

    private func handleCaptionEvent(_ event: RecognizedCaptionEvent) {
        appendCaptionToSubtitleExportSession(event)
        publishCaptionEventToRelay(event)
    }

    private func appendCaptionToSubtitleExportSession(_ event: RecognizedCaptionEvent) {
        guard var subtitleExportSession else {
            return
        }

        subtitleExportSession.append(event: event, inputLanguage: inputLanguage)
        self.subtitleExportSession = subtitleExportSession
    }

    private func publishCaptionEventToRelay(_ event: RecognizedCaptionEvent) {
        guard isCaptionSessionActive, relayConnectionStatus == .connected else {
            return
        }

        let settingsToPublish = relaySettings
        let speechKey = speechSettings.speechKey
        let relayInput = RelayCaptionPublishInput(
            event: event,
            inputLanguage: inputLanguage,
            outputLanguages: speechSettings.selectedOutputLanguages
        )

        Task.detached {
            for attempt in 1...relayPublishRetryLimit {
                do {
                    let result = try await settingsToPublish.publishCaptionEvent(
                        relayInput,
                        speechKey: speechKey
                    )

                    await MainActor.run {
                        relayLastPublishedAt = result.publishedAt
                    }
                    return
                } catch {
                    let message = error.localizedDescription

                    await MainActor.run {
                        appendLog(
                            level: attempt == relayPublishRetryLimit ? .error : .warning,
                            title: L10n.text("log.relay.publishFailed"),
                            detail: L10n.text("log.relay.publishFailedDetail", attempt, relayPublishRetryLimit, message)
                        )
                    }

                    guard attempt < relayPublishRetryLimit else {
                        await MainActor.run {
                            relayConnectionStatus = .failed
                            relayConnectionStatus.save()
                        }
                        return
                    }

                    try? await Task.sleep(for: .seconds(attempt))
                }
            }
        }
    }

    private func finishSubtitleExportSession() {
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
                : writtenFileURLs.map { $0.path(percentEncoded: false) }.joined(separator: "\n")
            appendLog(level: .info, title: L10n.text("log.srt.outputCompleted"), detail: detail)
            captionSessionStatus = .completed
        } catch {
            writeFallbackSubtitleFiles(for: subtitleExportSession, primaryError: error)
        }

        self.subtitleExportSession = nil
        sleepPreventionController.stopPreventingSleep()
    }

    private func writeFallbackSubtitleFiles(
        for subtitleExportSession: SubtitleExportSession,
        primaryError: Error
    ) {
        do {
            let writtenFileURLs = try subtitleExportSession.writeFallbackFiles()
            let detail = fallbackSubtitleExportDetail(
                primaryError: primaryError,
                fallbackFileURLs: writtenFileURLs,
                fallbackDirectoryURL: subtitleExportSession.fallbackDirectoryURL
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

    private func fallbackSubtitleExportDetail(
        primaryError: Error,
        fallbackFileURLs: [URL],
        fallbackDirectoryURL: URL
    ) -> String {
        let fallbackLocation = fallbackFileURLs.isEmpty
            ? fallbackDirectoryURL.path(percentEncoded: false)
            : fallbackFileURLs.map { $0.path(percentEncoded: false) }.joined(separator: "\n")

        return L10n.text("srt.fallbackDetail", primaryError.localizedDescription, fallbackLocation)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

private struct KeyboardEventBlocker: NSViewRepresentable {
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installMonitor()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var isEnabled = false
        private var monitor: Any?

        func installMonitor() {
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                self?.isEnabled == true ? nil : event
            }
        }

        func removeMonitor() {
            guard let monitor else {
                return
            }

            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        deinit {
            removeMonitor()
        }
    }
}

private final class SleepPreventionController {
    private var assertionIDs: [IOPMAssertionID] = []

    func startPreventingSleep() {
        guard assertionIDs.isEmpty else {
            return
        }

        assertionIDs = [
            createAssertion(type: kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString),
            createAssertion(type: kIOPMAssertionTypePreventUserIdleSystemSleep as CFString)
        ].compactMap { $0 }
    }

    func stopPreventingSleep() {
        assertionIDs.forEach { IOPMAssertionRelease($0) }
        assertionIDs.removeAll()
    }

    deinit {
        stopPreventingSleep()
    }

    private func createAssertion(type: CFString) -> IOPMAssertionID? {
        var assertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "LiveCaption Portal caption session" as CFString,
            &assertionID
        )

        guard result == kIOReturnSuccess else {
            return nil
        }

        return assertionID
    }
}
