// TelegramVoiceWaveform.swift

import Foundation

/// Decodes TDLib's `VoiceNote.waveform` - "a waveform representation of the voice note in 5-bit
/// format" - the exact same packed bitstream Telegram-iOS's own `AudioWaveform(bitstream:
/// bitsPerSample:)` decodes (`AudioWaveform.swift`), so this mirrors its bit-reading exactly: each
/// sample is 5 bits, read from a little-endian 32-bit window starting at that sample's bit offset,
/// giving values 0...31.
enum TelegramVoiceWaveform {
    static func decode(_ data: Data) -> [UInt8] {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return [] }
        let bitsPerSample = 5
        let numSamples = bytes.count * 8 / bitsPerSample
        var result = [UInt8]()
        result.reserveCapacity(numSamples)
        for index in 0..<numSamples {
            result.append(UInt8(bits(bytes, bitOffset: index * bitsPerSample, numBits: bitsPerSample)))
        }
        return result
    }

    private static func bits(_ bytes: [UInt8], bitOffset: Int, numBits: Int) -> UInt32 {
        let byteOffset = bitOffset / 8
        let bitInByte = bitOffset % 8
        var word: UInt32 = 0
        for i in 0..<4 {
            let index = byteOffset + i
            let byte: UInt32 = index < bytes.count ? UInt32(bytes[index]) : 0
            word |= byte << (8 * i)
        }
        let mask: UInt32 = (1 << numBits) - 1
        return (word >> UInt32(bitInByte)) & mask
    }
}
