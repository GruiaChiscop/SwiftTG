// TelegramVoiceNoteSending.swift

import Foundation
import TDLibKit

enum TelegramVoiceNoteSending {
    // MARK: Internal

    static func temporaryFileURL(
        in directory: URL? = nil,
        identifier: UUID = UUID(),
    ) -> URL {
        if let directory {
            return directory.appending(path: "voice_\(identifier.uuidString).ogg")
        }
        return TelegramOutgoingFileStaging.shared.voiceNoteFileURL(identifier: identifier)
    }

    static func waveform(from peakPowers: [Float]) -> Data {
        let levels = peakPowers.compactMap { peakPower -> UInt8? in
            let magnitude = abs(Int(peakPower))
            guard magnitude != 120, magnitude != 160 else { return nil }
            let level = 32 - Int(Double(magnitude) * 32 / 66)
            return UInt8(clamping: max(0, level))
        }
        .reduce(into: [UInt8]()) { result, level in
            if result.last != level {
                result.append(level)
            }
        }
        guard levels.contains(where: { $0 > 0 }) else { return Data() }
        return Data(pack(levels)).prefix(63)
    }

    static func content(
        url: URL,
        caption: FormattedText,
        duration: Int,
        waveform: Data,
    ) -> InputMessageContent {
        .inputMessageVoiceNote(.init(
            caption: caption,
            selfDestructType: nil,
            voiceNote: InputVoiceNote(
                duration: max(1, duration),
                voiceNote: .inputFileLocal(.init(path: TelegramMessageSending.localFilePath(url))),
                waveform: waveform,
            ),
        ))
    }

    static func send(
        service: any TelegramService,
        chatId: Int64,
        url: URL,
        caption: FormattedText,
        duration: Int,
        waveform: Data,
        replyTo: InputMessageReplyTo?,
        schedulingState: MessageSchedulingState? = nil,
    ) async throws {
        let caption = await TelegramTextFormatting.addingAutomaticEntities(service: service, to: caption)
        do {
            let messages = try await TelegramMessageSending.send(
                service: service,
                chatId: chatId,
                contents: [content(url: url, caption: caption, duration: duration, waveform: waveform)],
                replyTo: replyTo,
                uploadAction: .chatActionUploadingVoiceNote(.init(progress: 0)),
                schedulingState: schedulingState,
                onAccepted: { messages in
                    guard let message = messages.first else { return }
                    TelegramOutgoingFileStaging.shared.register(
                        fileURL: url,
                        chatId: chatId,
                        temporaryMessageId: message.id,
                    )
                },
            )
            guard !messages.isEmpty else {
                TelegramOutgoingFileStaging.shared.discard(fileURL: url)
                return
            }
        } catch {
            TelegramOutgoingFileStaging.shared.discard(fileURL: url)
            throw error
        }
    }

    // MARK: Private

    private static func pack(_ levels: [UInt8]) -> [UInt8] {
        var bytes = [UInt8]()
        var position = 0
        for level in levels {
            let index = bytes.count - 1
            switch position {
            case 0:
                bytes.append((level & 0b0001_1111) << 3)
            case 1:
                bytes[index] |= (level & 0b0001_1100) >> 2
                bytes.append((level & 0b0000_0011) << 6)
            case 2:
                bytes[index] |= (level & 0b0001_1111) << 1
            case 3:
                bytes[index] |= (level & 0b0001_0000) >> 4
                bytes.append((level & 0b0000_1111) << 4)
            case 4:
                bytes[index] |= (level & 0b0001_1110) >> 1
                bytes.append((level & 0b0000_0001) << 7)
            case 5:
                bytes[index] |= (level & 0b0001_1111) << 2
            case 6:
                bytes[index] |= (level & 0b0001_1000) >> 3
                bytes.append((level & 0b0000_0111) << 5)
            case 7:
                bytes[index] |= level
            default:
                break
            }
            position = position == 7 ? 0 : position + 1
        }
        return bytes
    }
}
