//
//  ContentView.swift
//  LiveCaptionPortal
//
//  Created by Hao Lee on 2026/4/26.
//

import SwiftUI

struct ContentView: View {
    @State private var inputLanguage = InputLanguage.mandarin
    @StateObject private var audioInputController = AudioInputController()
    @StateObject private var speechRecognitionController = SpeechRecognitionController()
    @State private var isCaptionSessionActive = false
    @State private var speechSettings: SpeechSettings
    @State private var speechAuthorizationStatus: SpeechAuthorizationStatus
    @State private var shouldVerifySpeechAuthorizationOnLaunch: Bool
    @State private var isLogDrawerExpanded = false
    @State private var selectedLogLevel = LogLevel.all
    @State private var logEntries: [LogEntry] = []
    private let windowMinimumSize = WindowLayout.minimumSize

    init() {
        let speechSettings = SpeechSettings.load()
        let authorizationStatus = SpeechAuthorizationStatus.load(for: speechSettings)
        let shouldVerifySpeechAuthorizationOnLaunch = authorizationStatus == .authorized

        _speechSettings = State(initialValue: speechSettings)
        _speechAuthorizationStatus = State(
            initialValue: shouldVerifySpeechAuthorizationOnLaunch ? .verifying : authorizationStatus
        )
        _shouldVerifySpeechAuthorizationOnLaunch = State(initialValue: shouldVerifySpeechAuthorizationOnLaunch)
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
            appendLog(level: .info, title: "Speech 授權重新驗證成功", detail: "Region \(result.region)")
        } catch {
            let message = error.localizedDescription
            speechAuthorizationStatus = .failed
            speechAuthorizationStatus.save()
            appendLog(level: .error, title: "Speech 授權重新驗證失敗", detail: message)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HeaderView(
                    isCaptionSessionActive: isCaptionSessionActive,
                    canToggleCaptionSession: audioInputController.isCapturing,
                    onToggleCaptionSession: toggleCaptionSession
                )

                Divider()

                HStack(alignment: .top, spacing: 0) {
                    ControlSidebar(
                        audioInputController: audioInputController,
                        speechAuthorizationStatus: speechAuthorizationStatus,
                        recognizedCaptionCount: speechRecognitionController.recognizedCaptionCount
                    )

                    Divider()

                    CaptionWorkspace(
                        inputLanguage: $inputLanguage,
                        outputLanguages: speechSettings.selectedOutputLanguages,
                        speechRecognitionController: speechRecognitionController
                    )

                    Divider()

                    StatusSidebar(
                        inputLanguage: inputLanguage,
                        speechSettings: $speechSettings,
                        speechAuthorizationStatus: $speechAuthorizationStatus
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
        .task {
            audioInputController.activate()
            await verifySpeechAuthorizationOnLaunchIfNeeded()
        }
        .onDisappear {
            audioInputController.stopCapture()
            speechRecognitionController.stopRecognition()
        }
        .onChange(of: isCaptionSessionActive) {
            updateSpeechRecognition()
        }
        .onChange(of: audioInputController.isCapturing) {
            if !audioInputController.isCapturing {
                isCaptionSessionActive = false
            } else {
                updateSpeechRecognition()
            }
        }
        .onChange(of: audioInputController.selectedDeviceID) {
            updateSpeechRecognition()
        }
        .onChange(of: inputLanguage) {
            updateSpeechRecognition()
        }
        .onChange(of: speechSettings) {
            updateSpeechRecognition()
        }
        .onChange(of: speechAuthorizationStatus) {
            updateSpeechRecognition()
        }
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

    private func toggleCaptionSession() {
        isCaptionSessionActive.toggle()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
