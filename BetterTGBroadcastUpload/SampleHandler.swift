// SampleHandler.swift

import CoreMedia
import Foundation
import ImageIO
import ReplayKit

// MARK: - SampleHandler

/// ReplayKit runs this object outside the main app. Frames are serialized into the shared App
/// Group exactly so the app can feed them to tgcalls' external video capturer.
final class SampleHandler: RPBroadcastSampleHandler {
    // MARK: Internal

    override func broadcastStarted(withSetupInfo _: [String: NSObject]?) {
        guard let directory = Self.sharedDirectory else {
            finishBroadcastWithError(Self.error("SwiftTG couldn't open its shared screen-share container."))
            return
        }
        isFinishing = false
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: directory.appending(path: Self.stopRequestName))
        let audioURL = directory.appending(path: Self.audioName)
        FileManager.default.createFile(atPath: audioURL.path, contents: nil)
        audioWriteHandle = try? FileHandle(forWritingTo: audioURL)
        try? Data().write(to: directory.appending(path: Self.extensionHeartbeatName), options: .atomic)
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {}

    override func broadcastFinished() {
        try? audioWriteHandle?.close()
        audioWriteHandle = nil
        guard let directory = Self.sharedDirectory else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: Self.extensionHeartbeatName))
        try? FileManager.default.removeItem(at: directory.appending(path: Self.frameName))
        try? FileManager.default.removeItem(at: directory.appending(path: Self.audioName))
        try? FileManager.default.removeItem(at: directory.appending(path: Self.stopRequestName))
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard !isFinishing, let directory = Self.sharedDirectory else { return }
        if FileManager.default.fileExists(atPath: directory.appending(path: Self.stopRequestName).path) {
            isFinishing = true
            BetterTGFinishBroadcastGracefully(self)
            return
        }
        guard Self.isCallActive(in: directory) else {
            isFinishing = true
            finishBroadcastWithError(Self.error("You're not in a voice chat"))
            return
        }

        switch sampleBufferType {
        case .video:
            processVideo(sampleBuffer, directory: directory)
        case .audioApp:
            processAppAudio(sampleBuffer)
        case .audioMic:
            break
        @unknown default:
            break
        }
    }

    // MARK: Private

    private static let appGroup = "group.com.gruiachiscop.BetterTG"
    private static let directoryName = "call-screen-share"
    private static let appHeartbeatName = "app-heartbeat"
    private static let extensionHeartbeatName = "extension-heartbeat"
    private static let frameName = "frame.bin"
    private static let audioName = "audio.bin"
    private static let stopRequestName = "stop-request"

    private static var sharedDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: directoryName, directoryHint: .isDirectory)
    }

    private var lastVideoTimestamp = -Double.infinity
    private var audioConverter: ScreenShareAudioConverter?
    private var audioWriteHandle: FileHandle?
    private var isFinishing = false

    private static func error(_ description: String) -> NSError {
        NSError(domain: "com.gruiachiscop.BetterTG.BroadcastUpload", code: 1, userInfo: [
            NSLocalizedDescriptionKey: description,
        ])
    }

    private static func isCallActive(in directory: URL) -> Bool {
        guard let data = try? Data(contentsOf: directory.appending(path: appHeartbeatName)),
              let string = String(data: data, encoding: .utf8),
              let timestamp = TimeInterval(string)
        else { return false }
        return Date().timeIntervalSince1970 - timestamp < 3
    }

    private static func serialize(pixelBuffer: CVPixelBuffer, sampleBuffer: CMSampleBuffer) -> Data? {
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            || pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        else { return nil }
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        guard let y = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let uv = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
        else { return nil }

        let orientation = (CMGetAttachment(
            sampleBuffer,
            key: RPVideoSampleOrientationKey as CFString,
            attachmentModeOut: nil,
        ) as? NSNumber)?.uint32Value ?? CGImagePropertyOrientation.up.rawValue
        let ySize = yStride * height
        let uvSize = uvStride * ((height + 1) / 2)
        var result = Data()
        for var value in [
            pixelFormat,
            UInt32(width),
            UInt32(height),
            UInt32(yStride),
            UInt32(uvStride),
            orientation,
        ] {
            withUnsafeBytes(of: &value) { result.append(contentsOf: $0) }
        }
        result.append(y.assumingMemoryBound(to: UInt8.self), count: ySize)
        result.append(uv.assumingMemoryBound(to: UInt8.self), count: uvSize)
        return result
    }

    private func processVideo(_ sampleBuffer: CMSampleBuffer, directory: URL) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let frame = Self.serialize(pixelBuffer: pixelBuffer, sampleBuffer: sampleBuffer)
        else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard !timestamp.isFinite || timestamp - lastVideoTimestamp >= 1.0 / 15.0 else { return }
        lastVideoTimestamp = timestamp

        try? frame.write(to: directory.appending(path: Self.frameName), options: .atomic)
        let heartbeat = Data(String(Date().timeIntervalSince1970).utf8)
        try? heartbeat.write(to: directory.appending(path: Self.extensionHeartbeatName), options: .atomic)
    }

    private func processAppAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else { return }
        let format = ScreenShareAudioConverter.Format(
            channelCount: Int(streamDescription.pointee.mChannelsPerFrame),
            sampleRate: Int(streamDescription.pointee.mSampleRate),
        )
        if audioConverter?.format != format {
            audioConverter = ScreenShareAudioConverter(streamDescription: streamDescription)
        }
        guard let audio = audioConverter?.convert(sampleBuffer), !audio.isEmpty else { return }
        var length = UInt32(audio.count)
        var packet = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        packet.append(audio)
        try? audioWriteHandle?.write(contentsOf: packet)
    }
}
