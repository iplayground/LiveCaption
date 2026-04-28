//
//  ContentView.swift
//  LiveCaptionPortal
//
//  Created by Hao Lee on 2026/4/26.
//

import SwiftUI
import AppKit
import AVFoundation
import Combine
import CoreAudio
import MicrosoftCognitiveServicesSpeech

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

private enum WindowLayout {
    static let controlSidebarWidth: CGFloat = 280
    static let statusSidebarWidth: CGFloat = 300
    static let audioSourcePickerWidth: CGFloat = 208
    static let logDrawerHeaderHeight: CGFloat = 50
    private static let preferredMinimumSize = CGSize(width: 1280, height: 820)

    static var minimumSize: CGSize {
        guard let visibleSize = NSScreen.main?.visibleFrame.size else {
            return preferredMinimumSize
        }

        return CGSize(
            width: min(preferredMinimumSize.width, visibleSize.width),
            height: min(preferredMinimumSize.height, visibleSize.height)
        )
    }
}

private enum ControlPalette {
    static let secondaryButtonBackground = Color.primary.opacity(0.08)
}

private enum InputLanguage: String, CaseIterable, Identifiable {
    case mandarin = "zh-TW"
    case english = "en-US"

    var id: String { rawValue }

    var speechLocale: String {
        rawValue
    }

    var matchingOutputLanguageID: String {
        switch self {
        case .mandarin:
            "zh-Hant"
        case .english:
            "en"
        }
    }

    var name: String {
        switch self {
        case .mandarin:
            "Chinese Traditional"
        case .english:
            "English"
        }
    }

    var nativeName: String {
        switch self {
        case .mandarin:
            "繁體中文"
        case .english:
            "English"
        }
    }

    var transcriptNativeName: String {
        switch self {
        case .mandarin:
            "繁體中文"
        case .english:
            "English"
        }
    }
}

private struct SpeechOutputLanguage: Identifiable {
    let code: String
    let name: String
    let nativeName: String
    let previewText: String

    var id: String { code }
}

private struct SpeechConnectionTestResult {
    let region: String
}

private enum SpeechRecognitionState {
    case idle
    case listening
    case recognizing
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            "等待語音"
        case .listening:
            "聆聽中"
        case .recognizing:
            "辨識中"
        case .failed:
            "辨識失敗"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "pause.circle"
        case .listening:
            "ear"
        case .recognizing:
            "waveform.badge.magnifyingglass"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            .secondary
        case .listening:
            .blue
        case .recognizing:
            .green
        case .failed:
            .red
        }
    }
}

private struct SpeechRecognitionRequest: Equatable {
    let region: String
    let speechKey: String
    let inputLocale: String
    let audioDeviceID: String
}

@MainActor
private final class SpeechRecognitionController: ObservableObject {
    @Published private(set) var state = SpeechRecognitionState.idle
    @Published private(set) var interimTranscript = ""
    @Published private(set) var finalTranscript = ""
    @Published private(set) var recognizedCaptionCount = 0

    private var recognizer: SPXSpeechRecognizer?
    private var activeRequest: SpeechRecognitionRequest?

    var displayTranscript: String {
        if !interimTranscript.isEmpty {
            return interimTranscript
        }

        if !finalTranscript.isEmpty {
            return finalTranscript
        }

        return "等待來源語音辨識結果。"
    }

    func startRecognition(
        settings: SpeechSettings,
        inputLanguage: InputLanguage,
        audioDeviceID: String?,
        authorizationStatus: SpeechAuthorizationStatus
    ) {
        let region = settings.region.trimmingCharacters(in: .whitespacesAndNewlines)
        let speechKey = settings.speechKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard authorizationStatus == .authorized else {
            stopRecognition(resetTranscript: false)
            state = .failed("Speech 尚未授權")
            return
        }

        guard !region.isEmpty, !speechKey.isEmpty else {
            stopRecognition(resetTranscript: false)
            state = .failed("缺少 Speech Region 或 Key")
            return
        }

        guard let audioDeviceID, !audioDeviceID.isEmpty else {
            stopRecognition(resetTranscript: false)
            state = .failed("尚未選擇音訊來源")
            return
        }

        let request = SpeechRecognitionRequest(
            region: region,
            speechKey: speechKey,
            inputLocale: inputLanguage.speechLocale,
            audioDeviceID: audioDeviceID
        )

        guard request != activeRequest || recognizer == nil else {
            return
        }

        stopRecognition(resetTranscript: false)
        activeRequest = request

        do {
            let speechConfiguration = try SPXSpeechConfiguration(
                subscription: speechKey,
                region: region
            )

            speechConfiguration.speechRecognitionLanguage = inputLanguage.speechLocale

            guard let audioConfiguration = SPXAudioConfiguration(microphone: audioDeviceID) else {
                throw SpeechRecognitionError.audioConfigurationFailed
            }

            let speechRecognizer = try SPXSpeechRecognizer(
                speechConfiguration: speechConfiguration,
                language: inputLanguage.speechLocale,
                audioConfiguration: audioConfiguration
            )

            configureEventHandlers(for: speechRecognizer)

            try speechRecognizer.startContinuousRecognition()

            recognizer = speechRecognizer
            state = .listening
        } catch {
            activeRequest = nil
            recognizer = nil
            state = .failed(error.localizedDescription)
        }
    }

    func stopRecognition(keepsCurrentTranscript: Bool = false) {
        stopRecognition(resetTranscript: !keepsCurrentTranscript)
    }

    private func stopRecognition(resetTranscript: Bool) {
        if let recognizer {
            try? recognizer.stopContinuousRecognition()
        }

        recognizer = nil
        activeRequest = nil
        state = .idle

        if resetTranscript {
            interimTranscript = ""
            finalTranscript = ""
            recognizedCaptionCount = 0
        }
    }

    private func configureEventHandlers(for recognizer: SPXSpeechRecognizer) {
        recognizer.addRecognizingEventHandler { [weak self] _, event in
            guard let text = event.result.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else {
                return
            }

            Task { @MainActor [weak self] in
                self?.interimTranscript = text
                self?.state = .recognizing
            }
        }

        recognizer.addRecognizedEventHandler { [weak self] _, event in
            let result = event.result
            guard result.reason == .recognizedSpeech,
                  let text = result.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else {
                return
            }

            Task { @MainActor [weak self] in
                self?.interimTranscript = ""
                self?.finalTranscript = text
                self?.recognizedCaptionCount += 1
                self?.state = .listening
            }
        }

        recognizer.addCanceledEventHandler { [weak self] _, event in
            let message = event.errorDetails?.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor [weak self] in
                self?.state = .failed(message?.isEmpty == false ? message! : "Speech 來源語音辨識已取消")
            }
        }
    }
}

private enum SpeechRecognitionError: LocalizedError {
    case audioConfigurationFailed

    var errorDescription: String? {
        switch self {
        case .audioConfigurationFailed:
            "無法建立音訊輸入設定"
        }
    }
}

private struct AudioInputDevice: Identifiable, Hashable {
    let id: String
    let name: String
}

private enum AudioPermissionState {
    case authorized
    case notDetermined
    case denied
    case restricted
    case unavailable

    var title: String {
        switch self {
        case .authorized:
            "已允許"
        case .notDetermined:
            "待確認"
        case .denied:
            "已拒絕"
        case .restricted:
            "受限制"
        case .unavailable:
            "不可用"
        }
    }

    var tint: Color {
        switch self {
        case .authorized:
            .green
        case .notDetermined:
            .orange
        case .denied, .restricted, .unavailable:
            .red
        }
    }

    var canRequestAccess: Bool {
        self == .notDetermined
    }

    static func currentMicrophoneState() -> AudioPermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            .authorized
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .unavailable
        }
    }
}

private final class AudioSampleBufferDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    var onLevelUpdate: ((Float) -> Void)?

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let rms = Self.rmsLevel(from: sampleBuffer) else {
            return
        }

        onLevelUpdate?(rms)
    }

    private static func rmsLevel(from sampleBuffer: CMSampleBuffer) -> Float? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return nil
        }

        var audioBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 0, mDataByteSize: 0, mData: nil)
        )
        var blockBuffer: CMBlockBuffer?

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr,
              let data = audioBufferList.mBuffers.mData,
              audioBufferList.mBuffers.mDataByteSize > 0
        else {
            return nil
        }

        let byteSize = Int(audioBufferList.mBuffers.mDataByteSize)
        let isFloat = streamDescription.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let bytesPerFrame = max(Int(streamDescription.pointee.mBytesPerFrame), 1)
        let frameCount = max(byteSize / bytesPerFrame, 1)

        if isFloat {
            let sampleCount = byteSize / MemoryLayout<Float>.size
            let samples = data.assumingMemoryBound(to: Float.self)
            var squareSum: Float = 0

            for index in 0..<sampleCount {
                let sample = samples[index]
                squareSum += sample * sample
            }

            return sqrt(squareSum / Float(max(sampleCount, 1)))
        }

        let sampleCount = byteSize / MemoryLayout<Int16>.size
        let samples = data.assumingMemoryBound(to: Int16.self)
        var squareSum: Float = 0

        for index in 0..<sampleCount {
            let sample = Float(samples[index]) / Float(Int16.max)
            squareSum += sample * sample
        }

        return sqrt(squareSum / Float(max(frameCount, 1)))
    }
}

@MainActor
private final class AudioInputController: ObservableObject, @unchecked Sendable {
    @Published private(set) var devices: [AudioInputDevice] = []
    @Published private(set) var selectedDeviceID: String?
    @Published private(set) var microphonePermission = AudioPermissionState.currentMicrophoneState()
    @Published private(set) var level: Float = 0
    @Published private(set) var peakLevel: Float = 0
    @Published private(set) var decibels: Float = AudioInputController.minimumDecibels
    @Published private(set) var isCaptureEnabled = false
    @Published private(set) var isCapturing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAutomaticNoiseCalibrationEnabled: Bool
    @Published var isMicrophoneSettingsPromptPresented = false

    private static let selectedDeviceDefaultsKey = "audioInput.selectedDeviceID"
    private static let selectedDeviceWasUserChosenDefaultsKey = "audioInput.selectedDeviceWasUserChosen"
    private static let automaticNoiseCalibrationDefaultsKey = "audioInput.automaticNoiseCalibrationEnabled"
    private static let minimumDecibels: Float = -80
    private static let noiseCalibrationDuration: TimeInterval = 1.5
    private static let noiseGateMarginDecibels: Float = 10
    private static let minimumAutomaticNoiseGateDecibels: Float = -70
    private static let maximumAutomaticNoiseGateDecibels: Float = -45
    private static let levelUpdateInterval: TimeInterval = 1.0 / 30.0
    private static let levelReleaseDecay: Float = 0.72
    private static let levelReleaseFloor: Float = 0.01
    private static let peakDecay: Float = 0.93
    private let sampleDelegate = AudioSampleBufferDelegate()
    private let sampleQueue = DispatchQueue(label: "io.iplayground.LiveCaptionPortal.audio-level")
    private var captureSession: AVCaptureSession?
    private var lastLevelUpdate = Date.distantPast
    private var noiseCalibrationStartedAt: Date?
    private var calibratedNoiseFloorDecibels: Float?
    private var selectedDeviceWasUserChosen: Bool

    init() {
        isAutomaticNoiseCalibrationEnabled = UserDefaults.standard.object(
            forKey: Self.automaticNoiseCalibrationDefaultsKey
        ) as? Bool ?? true
        selectedDeviceWasUserChosen = UserDefaults.standard.bool(forKey: Self.selectedDeviceWasUserChosenDefaultsKey)
        selectedDeviceID = selectedDeviceWasUserChosen
            ? UserDefaults.standard.string(forKey: Self.selectedDeviceDefaultsKey)
            : nil

        sampleDelegate.onLevelUpdate = { [weak self] rms in
            Task { @MainActor in
                self?.updateLevel(rms: rms)
            }
        }
    }

    var selectedDeviceName: String {
        guard let selectedDeviceID,
              let device = devices.first(where: { $0.id == selectedDeviceID })
        else {
            return "未選擇"
        }

        return device.name
    }

    var microphoneActionTitle: String {
        switch microphonePermission {
        case .authorized:
            isCapturing ? "收音中" : "可收音"
        case .notDetermined:
            "需要授權"
        case .denied:
            "已拒絕"
        case .restricted:
            "受限制"
        case .unavailable:
            "不可用"
        }
    }

    var canToggleCapture: Bool {
        switch microphonePermission {
        case .authorized, .notDetermined, .denied:
            selectedDeviceID != nil
        case .restricted, .unavailable:
            false
        }
    }

    func activate() {
        refreshDevices()
        refreshPermission()
    }

    func refreshDevices() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        let discoveredDevices = discoverySession.devices
            .filter { !Self.isVirtualAudioInputDevice($0) }
            .map { AudioInputDevice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        devices = discoveredDevices

        if selectedDeviceWasUserChosen,
           let selectedDeviceID,
           discoveredDevices.contains(where: { $0.id == selectedDeviceID }) {
            return
        }

        updateSelectedDeviceID(
            defaultAudioInputDeviceID(in: discoveredDevices) ?? discoveredDevices.first?.id,
            persistUserSelection: false
        )
    }

    func selectDevice(id: String?) {
        updateSelectedDeviceID(id, persistUserSelection: true)
    }

    func setCaptureEnabled(_ isEnabled: Bool) {
        if isEnabled {
            enableCapture()
        } else {
            isCaptureEnabled = false
            stopCaptureSession()
        }
    }

    func stopCapture() {
        isCaptureEnabled = false
        stopCaptureSession()
    }

    func setAutomaticNoiseCalibrationEnabled(_ isEnabled: Bool) {
        isAutomaticNoiseCalibrationEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.automaticNoiseCalibrationDefaultsKey)
        resetNoiseCalibration()

        if isCapturing, isEnabled {
            beginNoiseCalibration(at: Date())
        }
    }

    private func stopCaptureSession() {
        captureSession?.stopRunning()
        captureSession = nil
        isCapturing = false
        level = 0
        peakLevel = 0
        decibels = Self.minimumDecibels
        resetNoiseCalibration()
    }

    private func refreshPermission() {
        microphonePermission = AudioPermissionState.currentMicrophoneState()
    }

    private func requestMicrophoneAccess() {
        let controller = self
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor [controller] in
                controller.refreshPermission()

                if controller.microphonePermission == .authorized, controller.isCaptureEnabled {
                    controller.restartCapture()
                } else {
                    controller.isCaptureEnabled = false
                    controller.stopCaptureSession()
                }
            }
        }
    }

    private func enableCapture() {
        refreshPermission()
        isCaptureEnabled = true

        switch microphonePermission {
        case .authorized:
            restartCapture()
        case .notDetermined:
            requestMicrophoneAccess()
        case .denied:
            isCaptureEnabled = false
            errorMessage = "Portal 沒有麥克風權限。"
            isMicrophoneSettingsPromptPresented = true
        case .restricted, .unavailable:
            isCaptureEnabled = false
        }
    }

    func openMicrophoneSettingsAfterConfirmation() {
        isMicrophoneSettingsPromptPresented = false
        openMicrophonePrivacySettings()
    }

    private func restartCapture() {
        stopCaptureSession()
        refreshPermission()
        errorMessage = nil

        guard isCaptureEnabled else {
            return
        }

        guard microphonePermission == .authorized else {
            isCaptureEnabled = false
            return
        }

        guard let selectedDeviceID,
              let device = AVCaptureDevice(uniqueID: selectedDeviceID)
        else {
            errorMessage = "找不到音訊來源"
            return
        }

        do {
            let session = AVCaptureSession()
            session.beginConfiguration()

            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                errorMessage = "無法使用此音訊來源"
                session.commitConfiguration()
                return
            }
            session.addInput(input)

            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(sampleDelegate, queue: sampleQueue)
            guard session.canAddOutput(output) else {
                errorMessage = "無法讀取音訊音量"
                session.commitConfiguration()
                return
            }
            session.addOutput(output)

            session.commitConfiguration()
            captureSession = session
            session.startRunning()
            isCapturing = true
            beginNoiseCalibrationIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateLevel(rms: Float) {
        let now = Date()
        guard now.timeIntervalSince(lastLevelUpdate) >= Self.levelUpdateInterval else {
            return
        }
        lastLevelUpdate = now

        let safeRMS = max(rms, 0.0001)
        let rawDecibels = max(Self.minimumDecibels, min(0, 20 * log10(safeRMS)))
        let noiseGateDecibels = currentNoiseGateDecibels(rawDecibels: rawDecibels, at: now)
        let gatedDecibels = if let noiseGateDecibels, rawDecibels <= noiseGateDecibels {
            Self.minimumDecibels
        } else {
            rawDecibels
        }
        let rawLevel = max(0, min(1, (gatedDecibels - Self.minimumDecibels) / abs(Self.minimumDecibels)))
        let displayedLevel = rawLevel < level
            ? max(rawLevel, level * Self.levelReleaseDecay)
            : rawLevel
        let normalizedLevel = displayedLevel < Self.levelReleaseFloor ? 0 : displayedLevel
        let decayedPeakLevel = peakLevel * Self.peakDecay

        decibels = gatedDecibels
        level = normalizedLevel
        peakLevel = max(normalizedLevel, decayedPeakLevel < Self.levelReleaseFloor ? 0 : decayedPeakLevel)
    }

    private func beginNoiseCalibrationIfNeeded() {
        guard isAutomaticNoiseCalibrationEnabled else {
            return
        }

        beginNoiseCalibration(at: Date())
    }

    private func beginNoiseCalibration(at date: Date) {
        noiseCalibrationStartedAt = date
        calibratedNoiseFloorDecibels = nil
    }

    private func resetNoiseCalibration() {
        noiseCalibrationStartedAt = nil
        calibratedNoiseFloorDecibels = nil
    }

    private func currentNoiseGateDecibels(rawDecibels: Float, at date: Date) -> Float? {
        guard isAutomaticNoiseCalibrationEnabled else {
            return nil
        }

        if noiseCalibrationStartedAt == nil {
            beginNoiseCalibration(at: date)
        }

        if let startedAt = noiseCalibrationStartedAt,
           date.timeIntervalSince(startedAt) <= Self.noiseCalibrationDuration {
            let existingFloor = calibratedNoiseFloorDecibels ?? rawDecibels
            calibratedNoiseFloorDecibels = existingFloor + (rawDecibels - existingFloor) * 0.12
        }

        guard let calibratedNoiseFloorDecibels else {
            return nil
        }

        return max(
            Self.minimumAutomaticNoiseGateDecibels,
            min(
                Self.maximumAutomaticNoiseGateDecibels,
                calibratedNoiseFloorDecibels + Self.noiseGateMarginDecibels
            )
        )
    }

    private func saveSelectedDevice() {
        guard let selectedDeviceID else {
            UserDefaults.standard.removeObject(forKey: Self.selectedDeviceDefaultsKey)
            UserDefaults.standard.set(false, forKey: Self.selectedDeviceWasUserChosenDefaultsKey)
            return
        }

        UserDefaults.standard.set(selectedDeviceID, forKey: Self.selectedDeviceDefaultsKey)
        UserDefaults.standard.set(true, forKey: Self.selectedDeviceWasUserChosenDefaultsKey)
    }

    private func clearSavedSelectedDevice() {
        UserDefaults.standard.removeObject(forKey: Self.selectedDeviceDefaultsKey)
        UserDefaults.standard.set(false, forKey: Self.selectedDeviceWasUserChosenDefaultsKey)
    }

    private func defaultAudioInputDeviceID(in devices: [AudioInputDevice]) -> String? {
        guard let defaultDeviceID = systemDefaultAudioInputDeviceUID(),
              devices.contains(where: { $0.id == defaultDeviceID })
        else {
            return nil
        }

        return defaultDeviceID
    }

    private func updateSelectedDeviceID(_ deviceID: String?, persistUserSelection: Bool) {
        guard selectedDeviceID != deviceID else {
            if persistUserSelection {
                selectedDeviceWasUserChosen = true
                saveSelectedDevice()
            }
            return
        }

        selectedDeviceID = deviceID
        selectedDeviceWasUserChosen = persistUserSelection

        if persistUserSelection {
            saveSelectedDevice()
        } else {
            clearSavedSelectedDevice()
        }

        if isCaptureEnabled {
            restartCapture()
        }
    }

    private static func isVirtualAudioInputDevice(_ device: AVCaptureDevice) -> Bool {
        guard let audioDeviceID = coreAudioDeviceID(matchingUID: device.uniqueID),
              let transportType = transportType(for: audioDeviceID)
        else {
            return false
        }

        return transportType == kAudioDeviceTransportTypeVirtual
    }

    private static func coreAudioDeviceID(matchingUID uid: String) -> AudioDeviceID? {
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )

        guard sizeStatus == noErr, propertySize > 0 else {
            return nil
        }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(), count: deviceCount)

        let dataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )

        guard dataStatus == noErr else {
            return nil
        }

        return deviceIDs.first { deviceID in
            deviceUID(for: deviceID) == uid
        }
    }

    private static func transportType(for deviceID: AudioDeviceID) -> UInt32? {
        var transportType: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &transportType
        )

        guard status == noErr else {
            return nil
        }

        return transportType
    }

    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var deviceUID: Unmanaged<CFString>?
        var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let deviceUIDStatus = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceUID
        )

        guard deviceUIDStatus == noErr,
              let deviceUID
        else {
            return nil
        }

        return deviceUID.takeUnretainedValue() as String
    }

    private func systemDefaultAudioInputDeviceUID() -> String? {
        var defaultDeviceID = AudioDeviceID()
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let defaultDeviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultDeviceID
        )

        guard defaultDeviceStatus == noErr, defaultDeviceID != kAudioObjectUnknown else {
            return nil
        }

        return Self.deviceUID(for: defaultDeviceID)
    }

    private func openMicrophonePrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private enum SpeechSettingsValidationError: LocalizedError {
    case missingRegion
    case missingSpeechKey
    case serviceRejected(Int)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRegion:
            "尚未設定 Region"
        case .missingSpeechKey:
            "尚未設定 Speech Key"
        case .serviceRejected(let statusCode):
            "Azure Speech 拒絕連線，HTTP \(statusCode)"
        case .connectionFailed(let message):
            "Azure Speech 連線失敗：\(message)"
        }
    }
}

private struct SpeechSettings: Equatable {
    static let requiredOutputLanguageIDs: Set<String> = ["zh-Hant", "en"]
    static let defaultOutputLanguageIDs: Set<String> = ["zh-Hant", "en", "ja"]
    private static let userDefaults = UserDefaults.standard

    var region = ""
    var speechKey = ""
    var selectedOutputLanguageIDs = defaultOutputLanguageIDs {
        didSet {
            selectedOutputLanguageIDs.formUnion(Self.requiredOutputLanguageIDs)
        }
    }

    var hasAuthorizationMaterial: Bool {
        !speechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var regionSummary: String {
        region.isEmpty ? "尚未設定" : region
    }

    var outputLanguageSummary: String {
        "\(selectedOutputLanguageIDs.count) 種"
    }

    var selectedOutputLanguages: [SpeechOutputLanguage] {
        availableSpeechOutputLanguages.filter {
            selectedOutputLanguageIDs.contains($0.id)
        }
    }

    func testConnection() async throws -> SpeechConnectionTestResult {
        let normalizedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSpeechKey = speechKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedRegion.isEmpty else {
            throw SpeechSettingsValidationError.missingRegion
        }

        guard !normalizedSpeechKey.isEmpty else {
            throw SpeechSettingsValidationError.missingSpeechKey
        }

        let endpointURLString = "https://\(normalizedRegion).api.cognitive.microsoft.com/sts/v1.0/issueToken"

        guard let endpointURL = URL(string: endpointURLString) else {
            throw SpeechSettingsValidationError.connectionFailed("Region 格式無效")
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue(normalizedSpeechKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("0", forHTTPHeaderField: "Content-Length")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SpeechSettingsValidationError.connectionFailed("未收到 HTTP 回應")
            }

            guard (200..<300).contains(httpResponse.statusCode), !data.isEmpty else {
                throw SpeechSettingsValidationError.serviceRejected(httpResponse.statusCode)
            }
        } catch {
            if let validationError = error as? SpeechSettingsValidationError {
                throw validationError
            }

            throw SpeechSettingsValidationError.connectionFailed(error.localizedDescription)
        }

        return SpeechConnectionTestResult(region: normalizedRegion)
    }

    static func load() -> SpeechSettings {
        var settings = SpeechSettings()

        settings.region = userDefaults.string(forKey: UserDefaultsKey.region.rawValue) ?? ""
        settings.speechKey = userDefaults.string(forKey: UserDefaultsKey.speechKey.rawValue) ?? ""

        if let outputLanguageIDs = userDefaults.object(forKey: UserDefaultsKey.outputLanguageIDs.rawValue) as? [String] {
            settings.selectedOutputLanguageIDs = Set(outputLanguageIDs).union(requiredOutputLanguageIDs)
        }

        return settings
    }

    mutating func save() {
        Self.userDefaults.set(region, forKey: UserDefaultsKey.region.rawValue)
        Self.userDefaults.set(
            Array(selectedOutputLanguageIDs.union(Self.requiredOutputLanguageIDs)).sorted(),
            forKey: UserDefaultsKey.outputLanguageIDs.rawValue
        )
        if speechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Self.userDefaults.removeObject(forKey: UserDefaultsKey.speechKey.rawValue)
        } else {
            Self.userDefaults.set(speechKey, forKey: UserDefaultsKey.speechKey.rawValue)
        }
    }

    private enum UserDefaultsKey: String {
        case region = "speech.region"
        case speechKey = "speech.key"
        case outputLanguageIDs = "speech.outputLanguageIDs"
    }
}

private enum SpeechAuthorizationStatus: String {
    case unauthorized
    case unverified
    case verifying
    case authorized
    case failed

    private static let userDefaults = UserDefaults.standard
    private static let userDefaultsKey = "speech.authorizationStatus"

    static func load(for settings: SpeechSettings) -> SpeechAuthorizationStatus {
        guard settings.hasAuthorizationMaterial else {
            return .unauthorized
        }

        guard let rawValue = userDefaults.string(forKey: userDefaultsKey),
              let status = SpeechAuthorizationStatus(rawValue: rawValue),
              status != .unauthorized,
              status != .verifying else {
            return .unverified
        }

        return status
    }

    static func initial(for settings: SpeechSettings) -> SpeechAuthorizationStatus {
        settings.hasAuthorizationMaterial ? .unverified : .unauthorized
    }

    func save() {
        Self.userDefaults.set(rawValue, forKey: Self.userDefaultsKey)
    }

    var title: String {
        switch self {
        case .unauthorized:
            "未授權"
        case .unverified:
            "未驗證"
        case .verifying:
            "驗證中"
        case .authorized:
            "已授權"
        case .failed:
            "授權失敗"
        }
    }

    var tint: Color {
        switch self {
        case .unauthorized:
            .secondary
        case .unverified:
            .orange
        case .verifying:
            .blue
        case .authorized:
            .green
        case .failed:
            .red
        }
    }
}

private let availableSpeechOutputLanguages = [
    SpeechOutputLanguage(
        code: "zh-Hant",
        name: "Chinese Traditional",
        nativeName: "繁體中文",
        previewText: "歡迎來到今天的活動，字幕系統準備就緒。"
    ),
    SpeechOutputLanguage(
        code: "en",
        name: "English",
        nativeName: "English",
        previewText: "Welcome to today's event. The caption system is ready."
    ),
    SpeechOutputLanguage(
        code: "ja",
        name: "Japanese",
        nativeName: "日本語",
        previewText: "本日のイベントへようこそ。字幕システムの準備ができました。"
    ),
    SpeechOutputLanguage(
        code: "ko",
        name: "Korean",
        nativeName: "한국어",
        previewText: "오늘 행사에 오신 것을 환영합니다. 자막 시스템이 준비되었습니다."
    )
]

private enum LogLevel: String, CaseIterable, Identifiable {
    case all = "全部"
    case info = "Info"
    case warning = "Warning"
    case error = "Error"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .all:
            .secondary
        case .info:
            .blue
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}

private struct LogEntry: Identifiable {
    let id = UUID()
    let time: String
    let level: LogLevel
    let title: String
    let detail: String
}

private enum LogClock {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func currentTimeString() -> String {
        formatter.string(from: Date())
    }
}

private struct HeaderView: View {
    let isCaptionSessionActive: Bool
    let canToggleCaptionSession: Bool
    let onToggleCaptionSession: () -> Void

    private var captionButtonTitle: String {
        isCaptionSessionActive ? "停止字幕" : "開始字幕"
    }

    private var captionButtonSystemImage: String {
        isCaptionSessionActive ? "stop.fill" : "play.fill"
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LiveCaption Portal")
                    .font(.system(size: 22, weight: .semibold))
                Text("現場字幕操作台")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusPill(title: "Relay 未連線", systemImage: "antenna.radiowaves.left.and.right.slash", tint: .orange)

            Button {
                onToggleCaptionSession()
            } label: {
                Label(captionButtonTitle, systemImage: captionButtonSystemImage)
                    .frame(minWidth: 104)
            }
            .buttonStyle(
                CaptionSessionButtonStyle(
                    isEnabled: canToggleCaptionSession,
                    role: isCaptionSessionActive ? .stop : .start
                )
            )
            .controlSize(.large)
            .disabled(!canToggleCaptionSession)
            .help(canToggleCaptionSession ? captionButtonTitle : "請先開啟收音")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

private struct CaptionSessionButtonStyle: ButtonStyle {
    enum Role {
        case start
        case stop
    }

    let isEnabled: Bool
    let role: Role

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.72)
    }

    private var activeColor: Color {
        switch role {
        case .start:
            Color.accentColor
        case .stop:
            Color.red
        }
    }

    private var borderColor: Color {
        isEnabled ? activeColor.opacity(0.35) : Color.secondary.opacity(0.28)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else {
            return Color(nsColor: .controlBackgroundColor)
        }

        return isPressed ? activeColor.opacity(0.78) : activeColor
    }
}

private struct ControlSidebar: View {
    @ObservedObject var audioInputController: AudioInputController
    let speechAuthorizationStatus: SpeechAuthorizationStatus
    let recognizedCaptionCount: Int

    private var captureBinding: Binding<Bool> {
        Binding(
            get: { audioInputController.isCaptureEnabled },
            set: { audioInputController.setCaptureEnabled($0) }
        )
    }

    private var automaticNoiseCalibrationBinding: Binding<Bool> {
        Binding(
            get: { audioInputController.isAutomaticNoiseCalibrationEnabled },
            set: { audioInputController.setAutomaticNoiseCalibrationEnabled($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Panel(title: "工作階段", systemImage: "dot.radiowaves.left.and.right") {
                VStack(alignment: .leading, spacing: 12) {
                    SessionStatusValue()
                    SessionCaptureValue(isCapturing: audioInputController.isCapturing)
                    SpeechAuthorizationValue(status: speechAuthorizationStatus)
                    SessionMetricValue(label: "字幕事件", value: "\(recognizedCaptionCount)")
                }
            }

            Panel(title: "音訊輸入", systemImage: "mic", minHeight: 168) {
                Toggle("收音", isOn: captureBinding)
                    .font(.caption)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!audioInputController.canToggleCapture)
            } content: {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("來源")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                audioInputController.refreshDevices()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("重新掃描音訊來源")
                        }

                        AudioSourceMenu(
                            devices: audioInputController.devices,
                            selectedDeviceID: audioInputController.selectedDeviceID,
                            selectedDeviceName: audioInputController.selectedDeviceName,
                            isDisabled: audioInputController.devices.isEmpty
                        ) { deviceID in
                            audioInputController.selectDevice(id: deviceID)
                        }
                    }

                    AudioLevelMeter(
                        level: audioInputController.level,
                        peakLevel: audioInputController.peakLevel,
                        decibels: audioInputController.decibels
                    )

                    HStack {
                        Text("自動校準")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Toggle("自動校準", isOn: automaticNoiseCalibrationBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        PermissionRow(
                            title: "麥克風權限",
                            state: audioInputController.microphonePermission.title,
                            tint: audioInputController.microphonePermission.tint
                        )
                    }

                    if let errorMessage = audioInputController.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: WindowLayout.controlSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
        .alert("需要麥克風權限", isPresented: $audioInputController.isMicrophoneSettingsPromptPresented) {
            Button("取消", role: .cancel) {}
            Button("開啟系統設定") {
                audioInputController.openMicrophoneSettingsAfterConfirmation()
            }
        } message: {
            Text("Portal 需要麥克風權限才能收音。是否要前往系統設定調整權限？")
        }
    }
}

private struct CaptionWorkspace: View {
    @Binding var inputLanguage: InputLanguage
    let outputLanguages: [SpeechOutputLanguage]
    @ObservedObject var speechRecognitionController: SpeechRecognitionController

    private var previewLanguages: [SpeechOutputLanguage] {
        outputLanguages.filter { language in
            language.id != inputLanguage.matchingOutputLanguageID
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("字幕預覽")
                                .font(.title2.weight(.semibold))

                            StatusPill(
                                title: speechRecognitionController.state.title,
                                systemImage: speechRecognitionController.state.systemImage,
                                tint: speechRecognitionController.state.tint
                            )
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Text("語音語言")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker("語音語言", selection: $inputLanguage) {
                                ForEach(InputLanguage.allCases) { language in
                                    Text(language.nativeName).tag(language)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.trailing, 8)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "即時", systemImage: "waveform")

                        LiveTranscriptCard(
                            languageName: inputLanguage.name,
                            languageNativeName: inputLanguage.transcriptNativeName,
                            text: speechRecognitionController.displayTranscript
                        )

                        if case let .failed(message) = speechRecognitionController.state {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "預覽", systemImage: "captions.bubble")

                        VStack(spacing: 12) {
                            ForEach(previewLanguages) { language in
                                CaptionCard(
                                    languageName: language.name,
                                    languageNativeName: language.nativeName,
                                    text: language.previewText
                                )
                            }
                        }
                    }

                }
                .padding(24)
                .frame(width: geometry.size.width, alignment: .leading)
            }
            .scrollIndicators(.visible)
        }
    }
}

private struct StatusSidebar: View {
    let inputLanguage: InputLanguage
    @Binding var speechSettings: SpeechSettings
    @Binding var speechAuthorizationStatus: SpeechAuthorizationStatus
    let onLogEvent: (LogLevel, String, String) -> Void
    @State private var isSpeechSettingsPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Panel(title: "Speech", systemImage: "waveform.badge.magnifyingglass") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledValue(label: "Region", value: speechSettings.regionSummary)
                    LabeledValue(label: "語音語言", value: inputLanguage.nativeName)
                    LabeledValue(label: "字幕輸出", value: speechSettings.outputLanguageSummary)

                    Button {
                        isSpeechSettingsPresented = true
                    } label: {
                        Label("開啟設定", systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .sheet(isPresented: $isSpeechSettingsPresented) {
                SpeechSettingsSheet(
                    settings: $speechSettings,
                    isPresented: $isSpeechSettingsPresented
                ) { result in
                    speechAuthorizationStatus = .authorized
                    speechAuthorizationStatus.save()
                    onLogEvent(.info, "Speech 設定測試成功", "Region \(result.region)")
                } onFailure: { message in
                    speechAuthorizationStatus = .failed
                    speechAuthorizationStatus.save()
                    onLogEvent(.error, "Speech 設定測試失敗", message)
                } onAuthorizationSettingsChanged: {
                    speechAuthorizationStatus = .initial(for: speechSettings)
                    speechAuthorizationStatus.save()
                }
            }

            Panel(title: "Relay", systemImage: "server.rack") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledValue(label: "連線", value: "未設定")
                    LabeledValue(label: "環境", value: "Local")
                    LabeledValue(label: "最後送出", value: "尚無")

                    Button {
                    } label: {
                        Label("開啟設定", systemImage: "gearshape")
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Panel(title: "最近狀態", systemImage: "clock.badge") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledValue(label: "最後事件", value: "Relay 未連線")
                    LabeledValue(label: "警告", value: "1")
                    LabeledValue(label: "錯誤", value: "0")
                }
            }
        }
        .padding(20)
        .frame(width: WindowLayout.statusSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct SpeechSettingsSheet: View {
    @Binding var settings: SpeechSettings
    @Binding var isPresented: Bool
    let onConnectionTested: (SpeechConnectionTestResult) -> Void
    let onFailure: (String) -> Void
    let onAuthorizationSettingsChanged: () -> Void
    @State private var connectionTestStatus = SpeechConnectionTestStatus.idle
    @State private var activeConnectionTestID: UUID?

    private var canTestConnection: Bool {
        settings.hasAuthorizationMaterial && !settings.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var buildRequirementMessage: String {
        var missingItems: [String] = []

        if settings.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missingItems.append("Region")
        }

        if !settings.hasAuthorizationMaterial {
            missingItems.append("Speech Key")
        }

        guard !missingItems.isEmpty else {
            return "設定完整，可測試 Azure Speech 連線。"
        }

        return "補齊 \(missingItems.joined(separator: "、")) 後可測試。"
    }

    private var connectionHintMessage: String {
        connectionTestStatus.message.isEmpty ? buildRequirementMessage : connectionTestStatus.message
    }

    private var connectionHintTint: Color {
        connectionTestStatus.message.isEmpty
            ? (canTestConnection ? .green : .orange)
            : connectionTestStatus.tint
    }

    private func saveSettings() {
        settings.save()
    }

    private func testConnection() {
        settings.save()
        let testID = UUID()
        activeConnectionTestID = testID
        connectionTestStatus = .testing
        let settingsToTest = settings

        Task {
            do {
                let result = try await settingsToTest.testConnection()

                await MainActor.run {
                    guard activeConnectionTestID == testID else {
                        return
                    }

                    connectionTestStatus = .success
                    onConnectionTested(result)
                }
            } catch {
                let message = error.localizedDescription

                await MainActor.run {
                    guard activeConnectionTestID == testID else {
                        return
                    }

                    connectionTestStatus = .failure(message)
                    onFailure(message)
                }
            }
        }
    }

    private func markConnectionTestChanged() {
        activeConnectionTestID = nil
        connectionTestStatus = .idle
        onAuthorizationSettingsChanged()
    }

    var body: some View {
        VStack(spacing: 0) {
            SpeechSettingsHeader()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SpeechSettingsSection(title: "認證", systemImage: "key.horizontal") {
                        VStack(alignment: .leading, spacing: 14) {
                            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                                SpeechSettingsFieldRow(label: "Region") {
                                    TextField("例如：japaneast", text: $settings.region)
                                        .textFieldStyle(.roundedBorder)
                                }

                                SpeechSettingsFieldRow(label: "Speech Key") {
                                    SecureField("只保存在本機設定中", text: $settings.speechKey)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                    }

                    SpeechSettingsSection(title: "字幕輸出", systemImage: "captions.bubble") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(availableSpeechOutputLanguages) { language in
                                OutputLanguageToggleRow(
                                    language: language,
                                    isRequired: SpeechSettings.requiredOutputLanguageIDs.contains(language.id),
                                    selectedLanguageIDs: $settings.selectedOutputLanguageIDs
                                )
                            }
                        }
                    }

                    SpeechSettingsSection(title: "檢查", systemImage: "checkmark.seal") {
                        VStack(alignment: .leading, spacing: 12) {
                            SpeechSettingsStatusRow(
                                title: "連線測試",
                                state: connectionTestStatus.title,
                                tint: connectionTestStatus.tint
                            )

                            HStack {
                                SpeechConnectionTestButton(
                                    isEnabled: canTestConnection && !connectionTestStatus.isTesting,
                                    action: testConnection
                                )

                                Spacer()
                            }
                            .controlSize(.large)

                            Text(connectionHintMessage)
                                .font(.caption)
                                .foregroundStyle(connectionHintTint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Spacer()

                Button("完成") {
                    saveSettings()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(width: 640, height: 660)
        .onDisappear {
            saveSettings()
        }
        .onChange(of: settings.region) {
            markConnectionTestChanged()
        }
        .onChange(of: settings.speechKey) {
            markConnectionTestChanged()
        }
    }
}

private enum SpeechConnectionTestStatus {
    case idle
    case testing
    case success
    case failure(String)

    var title: String {
        switch self {
        case .idle:
            "尚未測試"
        case .testing:
            "測試中"
        case .success:
            "可連線"
        case .failure:
            "測試失敗"
        }
    }

    var message: String {
        switch self {
        case .idle:
            ""
        case .testing:
            "正在測試 Azure Speech 認證與區域設定。"
        case .success:
            "Azure Speech 測試成功。"
        case .failure(let message):
            message
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            .secondary
        case .testing:
            .blue
        case .success:
            .green
        case .failure:
            .red
        }
    }

    var isTesting: Bool {
        if case .testing = self {
            return true
        }

        return false
    }
}

private struct SpeechSettingsHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("Speech 設定")
                    .font(.title3.weight(.semibold))
                Text("Azure Speech SDK 連線與認證設定")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusPill(title: "SDK 1.43.0", systemImage: "shippingbox", tint: .blue)
        }
        .padding(24)
    }
}

private struct SpeechSettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: title, systemImage: systemImage)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SpeechSettingsFieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        GridRow {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            content
        }
    }
}

private struct SpeechConnectionTestButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            guard isEnabled else {
                return
            }

            action()
        } label: {
            Label("測試連線", systemImage: "network")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isEnabled ? Color.white : Color.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isEnabled ? Color.accentColor : Color(nsColor: .disabledControlTextColor).opacity(0.12))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isEnabled ? Color.accentColor.opacity(0.35) : Color(nsColor: .separatorColor),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.62)
        .accessibilityHint(isEnabled ? "測試 Azure Speech 設定" : "需要補齊 Region 與 Speech Key")
    }
}

private struct OutputLanguageToggleRow: View {
    let language: SpeechOutputLanguage
    let isRequired: Bool
    @Binding var selectedLanguageIDs: Set<String>

    private var isSelected: Binding<Bool> {
        Binding {
            isRequired || selectedLanguageIDs.contains(language.id)
        } set: { newValue in
            if isRequired {
                selectedLanguageIDs.insert(language.id)
            } else if newValue {
                selectedLanguageIDs.insert(language.id)
            } else {
                selectedLanguageIDs.remove(language.id)
            }
        }
    }

    var body: some View {
        Toggle(isOn: isSelected) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.nativeName)
                        .font(.subheadline.weight(.medium))
                    Text(language.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isRequired {
                    Text("必選")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(isRequired)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct SpeechSettingsStatusRow: View {
    let title: String
    let state: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)

            Text(title)
                .font(.subheadline)

            Spacer()

            Text(state)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
        }
    }
}

private struct LogDrawer: View {
    @Binding var isExpanded: Bool
    @Binding var selectedLevel: LogLevel
    let entries: [LogEntry]

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            LogDrawerHeader(
                isExpanded: $isExpanded,
                selectedLevel: $selectedLevel,
                entryCount: entries.count
            )

            if isExpanded {
                LogDrawerContent(entries: entries)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .shadow(color: .black.opacity(isExpanded ? 0.12 : 0), radius: 16, y: -4)
    }
}

private struct LogDrawerHeader: View {
    @Binding var isExpanded: Bool
    @Binding var selectedLevel: LogLevel
    let entryCount: Int
    @State private var isLevelPickerHidden = true

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.up")
                        .font(.subheadline.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.easeInOut(duration: 0.18), value: isExpanded)
                        .frame(width: 14, height: 14)

                    Text("事件紀錄")
                }
                .font(.headline)

                Text("最近 \(entryCount) 筆")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            levelPicker
                .opacity(isExpanded ? 1 : 0)
                .animation(.easeInOut(duration: 0.18), value: isExpanded)
                .disabled(!isExpanded)
                .accessibilityHidden(!isExpanded)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleLogDrawer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            toggleLogDrawer()
        }
        .onAppear {
            isLevelPickerHidden = !isExpanded
        }
        .onChange(of: isExpanded) { _, newValue in
            if newValue {
                return
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                guard !isExpanded else {
                    return
                }

                isLevelPickerHidden = true
            }
        }
    }

    private func toggleLogDrawer() {
        if isExpanded {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded = false
            }
            return
        }

        isLevelPickerHidden = false

        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded = true
            }
        }
    }

    @ViewBuilder
    private var levelPicker: some View {
        let picker = Picker("Log Level", selection: $selectedLevel) {
            ForEach(LogLevel.allCases) { level in
                Text(level.rawValue).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 320)

        if isLevelPickerHidden {
            picker.hidden()
        } else {
            picker
        }
    }
}

private struct LogDrawerContent: View {
    let entries: [LogEntry]

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            ScrollView {
                if entries.isEmpty {
                    ContentUnavailableView("尚無事件紀錄", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 56)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            LogEntryRow(entry: entry)

                            if entry.id != entries.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
    }
}

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            Text(entry.level.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(entry.level.tint)
                .frame(width: 64, alignment: .leading)

            Text(entry.title)
                .font(.subheadline.weight(.medium))
                .frame(width: 160, alignment: .leading)
                .lineLimit(1)

            Text(entry.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }
}

private struct Panel<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    var minHeight: CGFloat?
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String,
        minHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) where Accessory == EmptyView {
        self.title = title
        self.systemImage = systemImage
        self.minHeight = minHeight
        self.accessory = EmptyView()
        self.content = content()
    }

    init(
        title: String,
        systemImage: String,
        minHeight: CGFloat? = nil,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.minHeight = minHeight
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .labelStyle(.titleAndIcon)

                Spacer()

                accessory
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }
}

private struct CaptionCard: View {
    let languageName: String
    let languageNativeName: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(languageNativeName)
                        .font(.headline)
                    Text(languageName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(text)
                .font(.system(size: 24, weight: .regular))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.blue)
                .frame(width: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }
}

private struct LiveTranscriptCard: View {
    let languageName: String
    let languageNativeName: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(languageNativeName)
                        .font(.headline)
                    Text(languageName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(text)
                .font(.system(size: 28, weight: .medium))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.green)
                .frame(width: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }
}

private struct SectionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct AudioSourceMenu: View {
    let devices: [AudioInputDevice]
    let selectedDeviceID: String?
    let selectedDeviceName: String
    let isDisabled: Bool
    let onSelect: (String?) -> Void

    var body: some View {
        Menu {
            if devices.isEmpty {
                Text("未偵測到音訊來源")
            } else {
                ForEach(devices) { device in
                    Button {
                        onSelect(device.id)
                    } label: {
                        if device.id == selectedDeviceID {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedDeviceName)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.body.weight(.medium))
            .padding(.horizontal, 12)
            .frame(width: WindowLayout.audioSourcePickerWidth, height: 28, alignment: .leading)
            .background(ControlPalette.secondaryButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityLabel("音訊來源")
        .accessibilityValue(selectedDeviceName)
    }
}

private struct AudioLevelMeter: View {
    let level: Float
    let peakLevel: Float
    let decibels: Float

    private var decibelText: String {
        "\(Int(decibels.rounded())) dB"
    }

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.16))

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.green, .yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * CGFloat(level))

                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 2)
                        .offset(x: max(0, proxy.size.width * CGFloat(peakLevel) - 1))
                }
            }
            .frame(height: 12)
            .accessibilityLabel("音訊輸入音量")
            .accessibilityValue(decibelText)

            Text(decibelText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct StatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct LabeledValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .font(.subheadline)
    }
}

private struct SessionStatusValue: View {
    var body: some View {
        HStack {
            Text("狀態")
                .foregroundStyle(.secondary)

            Spacer()

            SessionStatusBadge(title: "尚未開始", systemImage: "pause.circle.fill", tint: .secondary)
        }
        .font(.subheadline)
    }
}

private struct SessionCaptureValue: View {
    let isCapturing: Bool

    private var title: String {
        isCapturing ? "收音中" : "未收音"
    }

    private var tint: Color {
        isCapturing ? .green : .orange
    }

    private var systemImage: String {
        isCapturing ? "waveform" : "mic.slash.fill"
    }

    var body: some View {
        HStack {
            Text("收音")
                .foregroundStyle(.secondary)

            Spacer()

            SessionStatusBadge(title: title, systemImage: systemImage, tint: tint)
        }
        .font(.subheadline)
    }
}

private struct SessionStatusBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(height: 22)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.36), lineWidth: 1)
            }
    }
}

private struct SessionMetricValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .frame(minWidth: 28, minHeight: 22)
                .background(Color.secondary.opacity(0.14), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.secondary.opacity(0.36), lineWidth: 1)
                }
        }
        .font(.subheadline)
    }
}

private struct SpeechAuthorizationValue: View {
    let status: SpeechAuthorizationStatus

    private var systemImage: String {
        switch status {
        case .unauthorized:
            "key.fill"
        case .unverified:
            "questionmark.circle.fill"
        case .verifying:
            "arrow.triangle.2.circlepath"
        case .authorized:
            "checkmark.seal.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack {
            Text("Speech 授權")
                .foregroundStyle(.secondary)

            Spacer()

            SessionStatusBadge(title: status.title, systemImage: systemImage, tint: status.tint)
        }
        .font(.subheadline)
    }
}

private struct PermissionRow: View {
    let title: String
    let state: String
    let tint: Color

    var body: some View {
        HStack {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text(state)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
