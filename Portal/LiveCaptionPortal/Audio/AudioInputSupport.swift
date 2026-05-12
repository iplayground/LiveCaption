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
    var onAudioPCM16Chunk: ((Data) -> Void)?
    private let levelUpdateInterval: TimeInterval = 1.0 / 30.0
    private var lastLevelUpdate = Date.distantPast

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if let pcm16Chunk = RealtimeAudioPCMConverter.pcm16Mono24k(from: sampleBuffer) {
            onAudioPCM16Chunk?(pcm16Chunk)
        }

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

enum RealtimeAudioPCMConverter {
    private static let targetSampleRate = 24_000.0

    static func pcm16Mono24k(from sampleBuffer: CMSampleBuffer) -> Data? {
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

        let description = streamDescription.pointee
        let byteSize = Int(audioBufferList.mBuffers.mDataByteSize)
        let bytesPerFrame = max(Int(description.mBytesPerFrame), 1)
        let frameCount = max(byteSize / bytesPerFrame, 1)
        let channelCount = max(Int(description.mChannelsPerFrame), 1)
        let sampleRate = description.mSampleRate > 0 ? description.mSampleRate : 48_000.0
        let isFloat = description.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let isSignedInteger = description.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0

        let monoSamples: [Float]
        if isFloat {
            monoSamples = floatMonoSamples(data: data, byteSize: byteSize, channelCount: channelCount)
        } else if isSignedInteger || description.mBitsPerChannel == 16 {
            monoSamples = int16MonoSamples(data: data, byteSize: byteSize, channelCount: channelCount)
        } else {
            return nil
        }

        guard !monoSamples.isEmpty else {
            return nil
        }

        return pcm16Data(from: resampled(monoSamples, sourceSampleRate: sampleRate), frameCount: frameCount)
    }

    private static func floatMonoSamples(
        data: UnsafeMutableRawPointer,
        byteSize: Int,
        channelCount: Int
    ) -> [Float] {
        let sampleCount = byteSize / MemoryLayout<Float>.size
        let samples = data.assumingMemoryBound(to: Float.self)
        let frameCount = sampleCount / channelCount

        return (0..<frameCount).map { frameIndex in
            let baseIndex = frameIndex * channelCount
            let channelSum = (0..<channelCount).reduce(Float(0)) { partialResult, channelIndex in
                partialResult + samples[baseIndex + channelIndex]
            }
            return channelSum / Float(channelCount)
        }
    }

    private static func int16MonoSamples(
        data: UnsafeMutableRawPointer,
        byteSize: Int,
        channelCount: Int
    ) -> [Float] {
        let sampleCount = byteSize / MemoryLayout<Int16>.size
        let samples = data.assumingMemoryBound(to: Int16.self)
        let frameCount = sampleCount / channelCount

        return (0..<frameCount).map { frameIndex in
            let baseIndex = frameIndex * channelCount
            let channelSum = (0..<channelCount).reduce(Float(0)) { partialResult, channelIndex in
                partialResult + Float(samples[baseIndex + channelIndex]) / Float(Int16.max)
            }
            return channelSum / Float(channelCount)
        }
    }

    private static func resampled(_ samples: [Float], sourceSampleRate: Double) -> [Float] {
        guard sourceSampleRate > 0, abs(sourceSampleRate - targetSampleRate) > 0.5 else {
            return samples
        }

        let outputCount = max(1, Int(Double(samples.count) * targetSampleRate / sourceSampleRate))
        return (0..<outputCount).map { outputIndex in
            let sourcePosition = Double(outputIndex) * sourceSampleRate / targetSampleRate
            let lowerIndex = min(Int(sourcePosition), samples.count - 1)
            let upperIndex = min(lowerIndex + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(lowerIndex))
            return samples[lowerIndex] + (samples[upperIndex] - samples[lowerIndex]) * fraction
        }
    }

    private static func pcm16Data(from samples: [Float], frameCount: Int) -> Data {
        var data = Data(capacity: max(samples.count, frameCount) * MemoryLayout<Int16>.size)
        for sample in samples {
            var value = Int16(max(Float(Int16.min), min(Float(Int16.max), sample * Float(Int16.max))))
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
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
