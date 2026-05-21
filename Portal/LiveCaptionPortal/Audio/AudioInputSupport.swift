import AVFoundation
import CoreAudio

enum RealtimeAudioPCMConverter {
    private static let targetSampleRate = 24_000.0
    private struct RetainedAudioBufferList {
        let pointer: UnsafeMutableRawPointer
        let blockBuffer: CMBlockBuffer?
    }

    static func pcm16Mono24k(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return nil
        }

        let description = streamDescription.pointee
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else {
            return nil
        }

        guard let retainedBufferList = retainedAudioBufferList(from: sampleBuffer) else {
            return nil
        }
        defer {
            retainedBufferList.pointer.deallocate()
        }

        _ = retainedBufferList.blockBuffer
        let buffers = UnsafeMutableAudioBufferListPointer(
            retainedBufferList.pointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        )
        let sampleRate = description.mSampleRate > 0 ? description.mSampleRate : 48_000.0
        let isFloat = description.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let isSignedInteger = description.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0

        let monoSamples: [Float]
        if isFloat {
            monoSamples = floatMonoSamples(
                from: buffers,
                description: description,
                frameCount: frameCount
            )
        } else if isSignedInteger {
            monoSamples = integerMonoSamples(
                from: buffers,
                description: description,
                frameCount: frameCount
            )
        } else {
            return nil
        }

        guard !monoSamples.isEmpty else {
            return nil
        }

        return pcm16Data(from: resampled(monoSamples, sourceSampleRate: sampleRate))
    }

    private static func retainedAudioBufferList(from sampleBuffer: CMSampleBuffer) -> RetainedAudioBufferList? {
        var audioBufferListSize = 0
        var blockBuffer: CMBlockBuffer?
        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &audioBufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard sizeStatus == noErr, audioBufferListSize > 0 else {
            return nil
        }

        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: audioBufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        guard fillAudioBufferList(
            pointer,
            size: audioBufferListSize,
            sampleBuffer: sampleBuffer,
            blockBuffer: &blockBuffer
        ) else {
            pointer.deallocate()
            return nil
        }

        return RetainedAudioBufferList(pointer: pointer, blockBuffer: blockBuffer)
    }

    private static func fillAudioBufferList(
        _ pointer: UnsafeMutableRawPointer,
        size: Int,
        sampleBuffer: CMSampleBuffer,
        blockBuffer: inout CMBlockBuffer?
    ) -> Bool {
        let audioBufferList = pointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        return status == noErr
    }

    private static func floatMonoSamples(
        from buffers: UnsafeMutableAudioBufferListPointer,
        description: AudioStreamBasicDescription,
        frameCount: Int
    ) -> [Float] {
        switch description.mBitsPerChannel {
        case 32:
            return monoSamples(
                from: buffers,
                frameCount: frameCount,
                bytesPerSample: MemoryLayout<Float>.size
            ) { data, index in
                data.assumingMemoryBound(to: Float.self)[index]
            }
        case 64:
            return monoSamples(
                from: buffers,
                frameCount: frameCount,
                bytesPerSample: MemoryLayout<Double>.size
            ) { data, index in
                Float(data.assumingMemoryBound(to: Double.self)[index])
            }
        default:
            return []
        }
    }

    private static func integerMonoSamples(
        from buffers: UnsafeMutableAudioBufferListPointer,
        description: AudioStreamBasicDescription,
        frameCount: Int
    ) -> [Float] {
        switch description.mBitsPerChannel {
        case 16:
            return monoSamples(
                from: buffers,
                frameCount: frameCount,
                bytesPerSample: MemoryLayout<Int16>.size
            ) { data, index in
                Float(data.assumingMemoryBound(to: Int16.self)[index]) / Float(Int16.max)
            }
        case 32:
            return monoSamples(
                from: buffers,
                frameCount: frameCount,
                bytesPerSample: MemoryLayout<Int32>.size
            ) { data, index in
                Float(data.assumingMemoryBound(to: Int32.self)[index]) / Float(Int32.max)
            }
        default:
            return []
        }
    }

    private static func monoSamples(
        from buffers: UnsafeMutableAudioBufferListPointer,
        frameCount: Int,
        bytesPerSample: Int,
        sampleValue: (UnsafeMutableRawPointer, Int) -> Float
    ) -> [Float] {
        var monoSamples: [Float] = []
        monoSamples.reserveCapacity(frameCount)

        for frameIndex in 0..<frameCount {
            var channelSum: Float = 0
            var channelCount = 0

            for buffer in buffers {
                guard let data = buffer.mData else {
                    continue
                }

                let channelsInBuffer = max(Int(buffer.mNumberChannels), 1)
                let sampleCount = Int(buffer.mDataByteSize) / bytesPerSample
                let availableFrames = sampleCount / channelsInBuffer
                guard frameIndex < availableFrames else {
                    continue
                }

                for channelIndex in 0..<channelsInBuffer {
                    channelSum += sampleValue(data, frameIndex * channelsInBuffer + channelIndex)
                    channelCount += 1
                }
            }

            if channelCount > 0 {
                monoSamples.append(channelSum / Float(channelCount))
            }
        }

        return monoSamples
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

    private static func pcm16Data(from samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            var value = Int16(max(Float(Int16.min), min(Float(Int16.max), sample * Float(Int16.max)))).littleEndian
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
