import SwiftUI
import AppKit
import AVFoundation
import Combine
import CoreAudio

struct AudioInputDevice: Identifiable, Hashable {
    let id: String
    let name: String
}

enum AudioPermissionState {
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

final class AudioSampleBufferDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
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
final class AudioInputController: ObservableObject, @unchecked Sendable {
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
