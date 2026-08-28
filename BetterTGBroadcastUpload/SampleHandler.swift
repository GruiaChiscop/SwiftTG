// SampleHandler.swift

import CoreMedia
import Darwin
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
        frameWriter = ScreenShareMappedFrameWriter(url: directory.appending(path: Self.frameMapName))
        openAudioPipeIfNeeded(in: directory)
        startHeartbeat(in: directory)
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {}

    override func broadcastFinished() {
        stopHeartbeat()
        frameWriter = nil
        closeAudioPipe()
        guard let directory = Self.sharedDirectory else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: Self.extensionHeartbeatName))
        try? FileManager.default.removeItem(at: directory.appending(path: Self.stopRequestName))
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard !isFinishing, let directory = Self.sharedDirectory else { return }
        if FileManager.default.fileExists(atPath: directory.appending(path: Self.stopRequestName).path) {
            isFinishing = true
            stopHeartbeat()
            BetterTGFinishBroadcastGracefully(self)
            return
        }
        guard Self.isCallActive(in: directory) else {
            isFinishing = true
            stopHeartbeat()
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
    private static let frameMapName = "frame.map"
    private static let audioPipeName = "audio.pipe"
    private static let stopRequestName = "stop-request"

    private static var sharedDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: directoryName, directoryHint: .isDirectory)
    }

    private var lastVideoTimestamp = -Double.infinity
    private var audioConverter: ScreenShareAudioConverter?
    private var frameWriter: ScreenShareMappedFrameWriter?
    private var audioFileDescriptor: Int32 = -1
    private var heartbeatTimer: DispatchSourceTimer?
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

        if frameWriter == nil {
            frameWriter = ScreenShareMappedFrameWriter(url: directory.appending(path: Self.frameMapName))
        }
        frameWriter?.write(frame)
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
        guard let directory = Self.sharedDirectory else { return }
        openAudioPipeIfNeeded(in: directory)
        guard audioFileDescriptor >= 0 else { return }

        // Writes no larger than PIPE_BUF are atomic. Splitting avoids corrupting the framed
        // stream if ReplayKit gives us a larger audio sample than the pipe can accept at once.
        let maximumAudioPayload = 4000
        var offset = 0
        while offset < audio.count {
            let count = min(maximumAudioPayload, audio.count - offset)
            var length = UInt32(count)
            var packet = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
            packet.append(audio.subdata(in: offset..<(offset + count)))
            let written = packet.withUnsafeBytes { bytes in
                Darwin.write(audioFileDescriptor, bytes.baseAddress, bytes.count)
            }
            guard written == packet.count else {
                closeAudioPipe()
                return
            }
            offset += count
        }
    }

    private func startHeartbeat(in directory: URL) {
        heartbeatTimer?.cancel()
        let heartbeatURL = directory.appending(path: Self.extensionHeartbeatName)
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler {
            let heartbeat = Data(String(Date().timeIntervalSince1970).utf8)
            try? heartbeat.write(to: heartbeatURL, options: .atomic)
        }
        heartbeatTimer = timer
        timer.resume()
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private func openAudioPipeIfNeeded(in directory: URL) {
        guard audioFileDescriptor < 0 else { return }
        let descriptor = Darwin.open(directory.appending(path: Self.audioPipeName).path, O_WRONLY | O_NONBLOCK)
        guard descriptor >= 0 else { return }
        _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
        audioFileDescriptor = descriptor
    }

    private func closeAudioPipe() {
        guard audioFileDescriptor >= 0 else { return }
        Darwin.close(audioFileDescriptor)
        audioFileDescriptor = -1
    }
}

// MARK: - ScreenShareMappedFrameWriter

/// The main app creates and owns this fixed-size mapping. ReplayKit only updates its contents,
/// matching Telegram-iOS's IPC design and avoiding a full atomic file replacement for every frame.
private final class ScreenShareMappedFrameWriter {
    // MARK: Lifecycle

    init?(url: URL) {
        let descriptor = Darwin.open(url.path, O_RDWR)
        guard descriptor >= 0 else { return nil }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_size >= Self.capacity else {
            Darwin.close(descriptor)
            return nil
        }
        guard let memory = mmap(nil, Self.capacity, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0),
              memory != MAP_FAILED
        else {
            Darwin.close(descriptor)
            return nil
        }
        self.descriptor = descriptor
        self.memory = memory
    }

    deinit {
        munmap(memory, Self.capacity)
        Darwin.close(descriptor)
    }

    // MARK: Internal

    func write(_ data: Data) {
        guard data.count <= Self.capacity - Self.headerSize,
              flock(descriptor, LOCK_EX | LOCK_NB) == 0
        else { return }
        defer { flock(descriptor, LOCK_UN) }

        var sequence = memory.load(fromByteOffset: 0, as: UInt32.self) &+ 1
        if sequence == 0 {
            sequence = 1
        }
        memory.storeBytes(of: UInt32(data.count), toByteOffset: MemoryLayout<UInt32>.size, as: UInt32.self)
        data.copyBytes(to: UnsafeMutableRawBufferPointer(
            start: memory.advanced(by: Self.headerSize),
            count: data.count,
        ))
        memory.storeBytes(of: sequence, toByteOffset: 0, as: UInt32.self)
    }

    // MARK: Private

    private static let capacity = 16 * 1024 * 1024
    private static let headerSize = MemoryLayout<UInt32>.size * 2

    private let descriptor: Int32
    private let memory: UnsafeMutableRawPointer
}
