// ScreenShareAudioConverter.swift

import AudioToolbox
import CoreMedia
import Foundation

// MARK: - ScreenShareAudioConverter

/// Converts ReplayKit app audio to the 48 kHz mono signed 16-bit PCM expected by tgcalls.
final class ScreenShareAudioConverter {
    // MARK: Lifecycle

    init(streamDescription: UnsafePointer<AudioStreamBasicDescription>) {
        self.format = Format(
            channelCount: Int(streamDescription.pointee.mChannelsPerFrame),
            sampleRate: Int(streamDescription.pointee.mSampleRate),
        )
    }

    // MARK: Internal

    struct Format: Equatable {
        let channelCount: Int
        let sampleRate: Int
    }

    let format: Format

    func convert(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let inputDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else { return nil }

        var bufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &bufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer,
        ) == noErr else { return nil }
        let byteCount = bufferList.mBuffers.mDataByteSize
        guard byteCount > 0, let bytes = bufferList.mBuffers.mData else { return nil }

        var outputDescription = AudioStreamBasicDescription(
            mSampleRate: 48000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0,
        )
        var converter: AudioConverterRef?
        guard AudioConverterNew(inputDescription, &outputDescription, &converter) == noErr,
              let converter
        else { return nil }
        defer { AudioConverterDispose(converter) }

        currentInputDescription = inputDescription
        currentBuffer = AudioBuffer(
            mNumberChannels: inputDescription.pointee.mChannelsPerFrame,
            mDataByteSize: byteCount,
            mData: bytes,
        )
        currentBufferOffset = 0

        let capacity = 65536
        var packetCount: UInt32?
        var output = Data(count: capacity)
        output.withUnsafeMutableBytes { outputBytes in
            var outputList = AudioBufferList()
            outputList.mNumberBuffers = 1
            outputList.mBuffers.mNumberChannels = 1
            outputList.mBuffers.mDataByteSize = UInt32(capacity)
            outputList.mBuffers.mData = outputBytes.baseAddress
            var requestedPackets = UInt32(capacity) / outputDescription.mBytesPerPacket
            if AudioConverterFillComplexBuffer(
                converter,
                screenShareAudioInput,
                Unmanaged.passUnretained(self).toOpaque(),
                &requestedPackets,
                &outputList,
                nil,
            ) == noErr {
                packetCount = requestedPackets
            }
        }

        guard let packetCount else { return nil }
        output.count = Int(packetCount * outputDescription.mBytesPerPacket)
        return output
    }

    // MARK: Fileprivate

    fileprivate var currentInputDescription: UnsafePointer<AudioStreamBasicDescription>?
    fileprivate var currentBuffer: AudioBuffer?
    fileprivate var currentBufferOffset: UInt32 = 0
}

// MARK: - Audio converter callback

private func screenShareAudioInput(
    _: AudioConverterRef,
    packetCount: UnsafeMutablePointer<UInt32>,
    audioData: UnsafeMutablePointer<AudioBufferList>,
    _: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
    userData: UnsafeMutableRawPointer?,
) -> OSStatus {
    guard let userData else {
        packetCount.pointee = 0
        return noErr
    }
    let converter = Unmanaged<ScreenShareAudioConverter>.fromOpaque(userData).takeUnretainedValue()
    guard let buffer = converter.currentBuffer,
          let description = converter.currentInputDescription,
          description.pointee.mBytesPerPacket > 0
    else {
        packetCount.pointee = 0
        return noErr
    }

    let bytesPerPacket = description.pointee.mBytesPerPacket
    let packetCapacity = buffer.mDataByteSize / bytesPerPacket
    let packetOffset = converter.currentBufferOffset / bytesPerPacket
    let providedPackets = min(packetCount.pointee, packetCapacity - packetOffset)
    packetCount.pointee = providedPackets

    audioData.pointee.mNumberBuffers = 1
    audioData.pointee.mBuffers.mData = buffer.mData?.advanced(by: Int(converter.currentBufferOffset))
    audioData.pointee.mBuffers.mDataByteSize = providedPackets * bytesPerPacket
    audioData.pointee.mBuffers.mNumberChannels = buffer.mNumberChannels
    converter.currentBufferOffset += providedPackets * bytesPerPacket
    return noErr
}
