import AVFoundation
import CoreAudio
import SwiftUI

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
            L10n.text("audioPermission.authorized")
        case .notDetermined:
            L10n.text("audioPermission.notDetermined")
        case .denied:
            L10n.text("audioPermission.denied")
        case .restricted:
            L10n.text("audioPermission.restricted")
        case .unavailable:
            L10n.text("audioPermission.unavailable")
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
    private let levelUpdateInterval: TimeInterval = 1.0 / 30.0
    private var lastLevelUpdate = Date.distantPast

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastLevelUpdate) >= levelUpdateInterval else {
            return
        }
        lastLevelUpdate = now

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

enum AudioInputDeviceResolver {
    static func isVirtualAudioInputDevice(_ device: AVCaptureDevice) -> Bool {
        guard let audioDeviceID = coreAudioDeviceID(matchingUID: device.uniqueID),
              let transportType = transportType(for: audioDeviceID)
        else {
            return false
        }

        return transportType == kAudioDeviceTransportTypeVirtual
    }

    static func systemDefaultAudioInputDeviceUID() -> String? {
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

        return deviceUID(for: defaultDeviceID)
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
}
