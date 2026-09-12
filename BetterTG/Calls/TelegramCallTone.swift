// TelegramCallTone.swift

import AudioToolbox
import Foundation

/// A Sendable PCM representation of one of Telegram-iOS's bundled call tones. The native call
/// audio device expects mono, signed 16-bit, little-endian samples at 48 kHz.
struct TelegramCallTone: Sendable {
    // MARK: Internal

    let samples: Data
    let sampleRate: Int
    let loopCount: Int

    static func load(resourceName: String, loopCount: Int) -> TelegramCallTone? {
        guard let url = resourceURL(named: resourceName) else {
            log("[Call] missing tone resource \(resourceName).mp3")
            return nil
        }

        var audioFile: ExtAudioFileRef?
        guard ExtAudioFileOpenURL(url as CFURL, &audioFile) == noErr, let audioFile else {
            log("[Call] could not open tone \(resourceName).mp3")
            return nil
        }
        defer { ExtAudioFileDispose(audioFile) }

        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: 48000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0,
        )
        let formatStatus = withUnsafePointer(to: &clientFormat) { format in
            ExtAudioFileSetProperty(
                audioFile,
                kExtAudioFileProperty_ClientDataFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
                format,
            )
        }
        guard formatStatus == noErr else {
            log("[Call] could not configure tone \(resourceName).mp3 (status=\(formatStatus))")
            return nil
        }

        var samples = Data()
        let framesPerChunk: UInt32 = 4096
        var bytes = [UInt8](repeating: 0, count: Int(framesPerChunk) * Int(clientFormat.mBytesPerFrame))
        while true {
            var frameCount = framesPerChunk
            let status = bytes.withUnsafeMutableBytes { storage in
                var buffers = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: clientFormat.mChannelsPerFrame,
                        mDataByteSize: UInt32(storage.count),
                        mData: storage.baseAddress,
                    ),
                )
                return ExtAudioFileRead(audioFile, &frameCount, &buffers)
            }
            guard status == noErr else {
                log("[Call] could not decode tone \(resourceName).mp3 (status=\(status))")
                return nil
            }
            guard frameCount > 0 else { break }
            samples.append(contentsOf: bytes.prefix(Int(frameCount) * Int(clientFormat.mBytesPerFrame)))
        }

        guard !samples.isEmpty else { return nil }
        return TelegramCallTone(samples: samples, sampleRate: 48000, loopCount: loopCount)
    }

    // MARK: Private

    private static func resourceURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "mp3")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Calls")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Resources/Calls")
    }
}
