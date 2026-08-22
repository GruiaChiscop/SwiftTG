// CallScreenShareReceiver.swift

import CoreMedia
import CoreVideo
import Foundation
import ImageIO
@preconcurrency import TgVoipWebrtc

// MARK: - CallScreenShareReceiver

/// Receives ReplayKit frames written by the Broadcast Upload extension and reconstructs the
/// sample buffers expected by tgcalls' external capturer. File work stays off the main actor.
final class CallScreenShareReceiver: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        frameReceived: @escaping @MainActor @Sendable (Frame) -> Void,
        audioReceived: @escaping @MainActor @Sendable (Data) -> Void,
        activeChanged: @escaping @MainActor @Sendable (Bool) -> Void,
    ) {
        self.frameReceived = frameReceived
        self.audioReceived = audioReceived
        self.activeChanged = activeChanged
    }

    // MARK: Internal

    struct Frame: @unchecked Sendable {
        let sampleBuffer: CMSampleBuffer
        let rotation: OngoingCallVideoOrientationWebrtc
    }

    func start() {
        queue.async { [weak self] in
            guard let self, timer == nil, let directory = Self.sharedDirectory else { return }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: directory.appending(path: Self.extensionHeartbeatName))
            try? FileManager.default.removeItem(at: directory.appending(path: Self.frameName))
            try? FileManager.default.removeItem(at: directory.appending(path: Self.stopRequestName))
            writeAppHeartbeat(in: directory)

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(67), leeway: .milliseconds(8))
            timer.setEventHandler { [weak self] in self?.poll(directory: directory) }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            lastFrameModificationDate = nil
            resetAudioReader()
            suppressesHeartbeat = false
            updateActive(false)
            guard let directory = Self.sharedDirectory else { return }
            try? FileManager.default.removeItem(at: directory.appending(path: Self.appHeartbeatName))
            try? FileManager.default.removeItem(at: directory.appending(path: Self.stopRequestName))
        }
    }

    func requestBroadcastStop() {
        queue.async { [self] in
            suppressesHeartbeat = true
            guard let directory = Self.sharedDirectory else { return }
            try? Data().write(to: directory.appending(path: Self.stopRequestName), options: .atomic)
            try? FileManager.default.removeItem(at: directory.appending(path: Self.appHeartbeatName))
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
    private static let headerSize = MemoryLayout<UInt32>.size * 6

    private static var sharedDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: directoryName, directoryHint: .isDirectory)
    }

    private let frameReceived: @MainActor @Sendable (Frame) -> Void
    private let audioReceived: @MainActor @Sendable (Data) -> Void
    private let activeChanged: @MainActor @Sendable (Bool) -> Void
    private let queue = DispatchQueue(label: "com.gruiachiscop.BetterTG.call-screen-share", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var lastFrameModificationDate: Date?
    private var isActive = false
    private var lastHeartbeatWrite = Date.distantPast
    private var suppressesHeartbeat = false
    private var audioReadHandle: FileHandle?
    private var pendingAudioData = Data()

    private static func isExtensionActive(in directory: URL, now: Date) -> Bool {
        guard let data = try? Data(contentsOf: directory.appending(path: extensionHeartbeatName)),
              let string = String(data: data, encoding: .utf8),
              let timestamp = TimeInterval(string)
        else { return false }
        return now.timeIntervalSince1970 - timestamp < 2
    }

    private static func decodeFrame(_ data: Data) -> Frame? {
        guard data.count >= headerSize else { return nil }
        let values: [UInt32] = data.withUnsafeBytes { bytes in
            (0..<6).map {
                bytes.loadUnaligned(fromByteOffset: $0 * MemoryLayout<UInt32>.size, as: UInt32.self)
            }
        }
        let pixelFormat = OSType(values[0])
        let width = Int(values[1])
        let height = Int(values[2])
        let yStride = Int(values[3])
        let uvStride = Int(values[4])
        guard width > 0, height > 0, yStride >= width, uvStride >= width else { return nil }

        let uvHeight = (height + 1) / 2
        let ySize = yStride.multipliedReportingOverflow(by: height)
        let uvSize = uvStride.multipliedReportingOverflow(by: uvHeight)
        guard !ySize.overflow, !uvSize.overflow,
              headerSize + ySize.partialValue + uvSize.partialValue == data.count
        else { return nil }

        var pixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            attributes,
            &pixelBuffer,
        ) == kCVReturnSuccess, let pixelBuffer else { return nil }

        guard CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let destinationY = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let destinationUV = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
        else { return nil }
        let destinationYStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let destinationUVStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)

        data.withUnsafeBytes { bytes in
            guard let source = bytes.baseAddress else { return }
            let sourceY = source.advanced(by: headerSize)
            let sourceUV = source.advanced(by: headerSize + ySize.partialValue)
            for row in 0..<height {
                memcpy(
                    destinationY.advanced(by: row * destinationYStride),
                    sourceY.advanced(by: row * yStride),
                    min(yStride, destinationYStride),
                )
            }
            for row in 0..<uvHeight {
                memcpy(
                    destinationUV.advanced(by: row * destinationUVStride),
                    sourceUV.advanced(by: row * uvStride),
                    min(uvStride, destinationUVStride),
                )
            }
        }

        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription,
        ) == noErr, let formatDescription else { return nil }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid,
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer,
        ) == noErr, let sampleBuffer else { return nil }

        return Frame(sampleBuffer: sampleBuffer, rotation: rotation(for: values[5]))
    }

    private static func rotation(for rawOrientation: UInt32) -> OngoingCallVideoOrientationWebrtc {
        switch CGImagePropertyOrientation(rawValue: rawOrientation) {
        case .right, .rightMirrored:
            .orientation90
        case .down, .downMirrored:
            .orientation180
        case .left, .leftMirrored:
            .orientation270
        default:
            .orientation0
        }
    }

    private func poll(directory: URL) {
        let now = Date()
        if !suppressesHeartbeat, now.timeIntervalSince(lastHeartbeatWrite) >= 1 {
            writeAppHeartbeat(in: directory)
        }

        let extensionIsActive = Self.isExtensionActive(in: directory, now: now)
        updateActive(extensionIsActive)
        guard extensionIsActive else {
            lastFrameModificationDate = nil
            resetAudioReader()
            if suppressesHeartbeat {
                suppressesHeartbeat = false
                try? FileManager.default.removeItem(at: directory.appending(path: Self.stopRequestName))
                writeAppHeartbeat(in: directory)
            }
            return
        }

        pollAudio(directory: directory)

        let frameURL = directory.appending(path: Self.frameName)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: frameURL.path),
              let modificationDate = attributes[.modificationDate] as? Date,
              modificationDate != lastFrameModificationDate,
              let data = try? Data(contentsOf: frameURL, options: .mappedIfSafe),
              let frame = Self.decodeFrame(data)
        else { return }
        lastFrameModificationDate = modificationDate
        Task { @MainActor [frameReceived] in frameReceived(frame) }
    }

    private func writeAppHeartbeat(in directory: URL) {
        let now = Date()
        lastHeartbeatWrite = now
        let heartbeat = Data(String(now.timeIntervalSince1970).utf8)
        try? heartbeat.write(to: directory.appending(path: Self.appHeartbeatName), options: .atomic)
    }

    private func updateActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        Task { @MainActor [activeChanged] in activeChanged(active) }
    }

    private func pollAudio(directory: URL) {
        if audioReadHandle == nil {
            audioReadHandle = try? FileHandle(forReadingFrom: directory.appending(path: Self.audioName))
        }
        guard let chunk = try? audioReadHandle?.readToEnd(), !chunk.isEmpty else { return }
        pendingAudioData.append(chunk)

        while pendingAudioData.count >= MemoryLayout<UInt32>.size {
            let length = pendingAudioData.withUnsafeBytes {
                Int($0.loadUnaligned(as: UInt32.self))
            }
            guard length > 0, length <= 1_048_576 else {
                resetAudioReader()
                return
            }
            let packetSize = MemoryLayout<UInt32>.size + length
            guard pendingAudioData.count >= packetSize else { return }
            let audio = pendingAudioData.subdata(in: MemoryLayout<UInt32>.size..<packetSize)
            pendingAudioData.removeSubrange(0..<packetSize)
            Task { @MainActor [audioReceived] in audioReceived(audio) }
        }
    }

    private func resetAudioReader() {
        try? audioReadHandle?.close()
        audioReadHandle = nil
        pendingAudioData.removeAll(keepingCapacity: true)
    }
}
