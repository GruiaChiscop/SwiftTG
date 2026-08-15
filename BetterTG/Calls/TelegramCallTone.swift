// TelegramCallTone.swift

import AVFoundation
import CoreMedia
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

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM as NSNumber,
            AVSampleRateKey: 48000 as NSNumber,
            AVLinearPCMBitDepthKey: 16 as NSNumber,
            AVLinearPCMIsNonInterleaved: false as NSNumber,
            AVLinearPCMIsFloatKey: false as NSNumber,
            AVLinearPCMIsBigEndianKey: false as NSNumber,
            AVNumberOfChannelsKey: 1 as NSNumber,
        ]
        let asset = AVURLAsset(url: url)

        guard let reader = try? AVAssetReader(asset: asset) else {
            log("[Call] could not create audio reader for \(resourceName).mp3")
            return nil
        }
        let output = AVAssetReaderAudioMixOutput(audioTracks: asset.tracks, audioSettings: outputSettings)
        guard reader.canAdd(output) else {
            log("[Call] could not decode tone \(resourceName).mp3")
            return nil
        }
        reader.add(output)
        guard reader.startReading() else {
            log("[Call] could not start decoding tone \(resourceName).mp3")
            return nil
        }

        var samples = Data()
        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            var audioBufferList = AudioBufferList()
            var retainedBlockBuffer: CMBlockBuffer?
            let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                sampleBuffer,
                bufferListSizeNeededOut: nil,
                bufferListOut: &audioBufferList,
                bufferListSize: MemoryLayout<AudioBufferList>.size,
                blockBufferAllocator: nil,
                blockBufferMemoryAllocator: nil,
                flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                blockBufferOut: &retainedBlockBuffer,
            )
            guard status == noErr else {
                log("[Call] could not read samples from \(resourceName).mp3 (status=\(status))")
                return nil
            }

            let size = Int(CMSampleBufferGetTotalSampleSize(sampleBuffer))
            if size > 0, let bytes = audioBufferList.mBuffers.mData {
                samples.append(bytes.assumingMemoryBound(to: UInt8.self), count: size)
            }
            _ = retainedBlockBuffer
        }

        guard reader.status == .completed, !samples.isEmpty else {
            log(
                "[Call] tone decoding failed for \(resourceName).mp3: \(reader.error?.localizedDescription ?? "unknown error")",
            )
            return nil
        }
        return TelegramCallTone(samples: samples, sampleRate: 48000, loopCount: loopCount)
    }

    // MARK: Private

    private static func resourceURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "mp3")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Calls")
            ?? Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "Resources/Calls")
    }
}
