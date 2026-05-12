import SwiftUI
import AppKit
import AVFoundation
import Combine

@MainActor
final class AudioLevelState: ObservableObject {
    @Published fileprivate(set) var level: Float = 0
    @Published fileprivate(set) var peakLevel: Float = 0
    @Published fileprivate(set) var decibels: Float = AudioInputController.minimumDecibels

    fileprivate func reset() {
        level = 0
        peakLevel = 0
        decibels = AudioInputController.minimumDecibels
    }
}

@MainActor
final class AudioInputController: ObservableObject, @unchecked Sendable {
    @Published private(set) var devices: [AudioInputDevice] = []
    @Published private(set) var selectedDeviceID: String?
    @Published private(set) var microphonePermission = AudioPermissionState.currentMicrophoneState()
    @Published private(set) var isCaptureEnabled = false
    @Published private(set) var isCapturing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isAutomaticNoiseCalibrationEnabled: Bool
    @Published var isMicrophoneSettingsPromptPresented = false
    var onAudioPCM16Chunk: ((Data) -> Void)? {
        didSet {
            sampleDelegate.onAudioPCM16Chunk = onAudioPCM16Chunk
        }
    }
    let levelState = AudioLevelState()

    private static let selectedDeviceDefaultsKey = "audioInput.selectedDeviceID"
    private static let selectedDeviceWasUserChosenDefaultsKey = "audioInput.selectedDeviceWasUserChosen"
    private static let automaticNoiseCalibrationDefaultsKey = "audioInput.automaticNoiseCalibrationEnabled"
    fileprivate static let minimumDecibels: Float = -80
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
            return L10n.text("audio.noSourceSelected")
        }

        return device.name
    }

    var microphoneActionTitle: String {
        switch microphonePermission {
        case .authorized:
            isCapturing ? L10n.text("audio.capturing") : L10n.text("audio.readyToCapture")
        case .notDetermined:
            L10n.text("audio.needsAuthorization")
        case .denied:
            L10n.text("audioPermission.denied")
        case .restricted:
            L10n.text("audioPermission.restricted")
        case .unavailable:
            L10n.text("audioPermission.unavailable")
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
            .filter { !AudioInputDeviceResolver.isVirtualAudioInputDevice($0) }
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
        levelState.reset()
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
            errorMessage = L10n.text("audio.error.noMicrophonePermission")
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
            errorMessage = L10n.text("audio.error.sourceNotFound")
            return
        }

        do {
            let session = AVCaptureSession()
            session.beginConfiguration()

            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                errorMessage = L10n.text("audio.error.sourceUnavailable")
                session.commitConfiguration()
                return
            }
            session.addInput(input)

            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(sampleDelegate, queue: sampleQueue)
            guard session.canAddOutput(output) else {
                errorMessage = L10n.text("audio.error.levelUnavailable")
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
        let displayedLevel = rawLevel < levelState.level
            ? max(rawLevel, levelState.level * Self.levelReleaseDecay)
            : rawLevel
        let normalizedLevel = displayedLevel < Self.levelReleaseFloor ? 0 : displayedLevel
        let decayedPeakLevel = levelState.peakLevel * Self.peakDecay

        levelState.decibels = gatedDecibels
        levelState.level = normalizedLevel
        levelState.peakLevel = max(normalizedLevel, decayedPeakLevel < Self.levelReleaseFloor ? 0 : decayedPeakLevel)
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
        guard let defaultDeviceID = AudioInputDeviceResolver.systemDefaultAudioInputDeviceUID(),
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

    private func openMicrophonePrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
