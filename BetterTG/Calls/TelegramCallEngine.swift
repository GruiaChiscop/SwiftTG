// TelegramCallEngine.swift

import Foundation
@preconcurrency import TgVoipWebrtc

/// Owns every tgcalls object and touches it only from the serial queue supplied to tgcalls.
/// `OngoingCallThreadLocalContextWebrtc` asserts this contract in debug builds, including during
/// construction and teardown, so the objects must never escape this wrapper.
final class TelegramCallEngine: @unchecked Sendable {
    // MARK: Lifecycle

    init() {
        self.contextQueue = CallContextQueue(queue: queue)
    }

    // MARK: Internal

    enum State: Equatable, Sendable {
        case initializing
        case connected
        case failed
        case reconnecting
        case unknown(Int32)
    }

    enum NetworkKind: Sendable {
        case wifi
        case cellular
    }

    struct Connection: Sendable {
        let reflectorId: UInt8
        let hasStun: Bool
        let hasTurn: Bool
        let hasTcp: Bool
        let ip: String
        let port: Int32
        let username: String
        let password: String
    }

    struct Configuration: Sendable {
        let version: String
        let customParameters: String?
        let encryptionKey: Data
        let isOutgoing: Bool
        let connections: [Connection]
        let maxLayer: Int32
        let allowP2P: Bool
    }

    struct StopResult: Sendable {
        let callLog: String?
        let debugInformation: String?
    }

    func start(
        configuration: Configuration,
        muted: Bool,
        lowBattery: Bool,
        audioSessionActive: Bool,
        networkKind: NetworkKind,
        sendSignaling: @escaping @Sendable (Data) -> Void,
        stateChanged: @escaping @Sendable (State) -> Void,
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            let pendingSignaling = pendingSignaling
            stopLocked(clearPendingSignaling: false)
            self.pendingSignaling = pendingSignaling
            isMuted = muted
            isLowBattery = lowBattery
            isAudioSessionActive = audioSessionActive
            self.networkKind = networkKind

            let generation = UUID()
            self.generation = generation
            let audioDevice = SharedCallAudioDevice(disableRecording: false, enableSystemMute: false)
            let connections = configuration.connections.map {
                OngoingCallConnectionDescriptionWebrtc(
                    reflectorId: $0.reflectorId,
                    hasStun: $0.hasStun,
                    hasTurn: $0.hasTurn,
                    hasTcp: $0.hasTcp,
                    ip: $0.ip,
                    port: $0.port,
                    username: $0.username,
                    password: $0.password,
                )
            }
            let context = OngoingCallThreadLocalContextWebrtc(
                version: configuration.version,
                customParameters: configuration.customParameters,
                queue: contextQueue,
                proxy: nil,
                networkType: Self.networkType(for: networkKind),
                dataSaving: .never,
                derivedState: Data(),
                key: configuration.encryptionKey,
                isOutgoing: configuration.isOutgoing,
                connections: connections,
                maxLayer: configuration.maxLayer,
                allowP2P: configuration.allowP2P,
                allowTCP: true,
                enableStunMarking: true,
                logPath: "",
                statsLogPath: "",
                sendSignalingData: sendSignaling,
                videoCapturer: nil,
                preferredVideoCodec: nil,
                audioInputDeviceId: "",
                audioDevice: audioDevice,
                directConnection: nil,
            )
            context.stateChanged = { [weak self] state, _, _, _, _, _ in
                guard let self, self.generation == generation else { return }
                stateChanged(Self.state(from: state))
            }

            self.audioDevice = audioDevice
            self.context = context
            context.setIsMuted(muted)
            context.setIsLowBatteryLevel(lowBattery)
            audioDevice.setManualAudioSessionIsActive(audioSessionActive)
            for data in self.pendingSignaling {
                context.addSignaling(data)
            }
            self.pendingSignaling.removeAll(keepingCapacity: true)
        }
    }

    func addSignaling(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            if let context {
                context.addSignaling(data)
            } else {
                pendingSignaling.append(data)
            }
        }
    }

    func setMuted(_ muted: Bool) {
        queue.async { [weak self] in
            self?.isMuted = muted
            self?.context?.setIsMuted(muted)
        }
    }

    func setLowBattery(_ lowBattery: Bool) {
        queue.async { [weak self] in
            self?.isLowBattery = lowBattery
            self?.context?.setIsLowBatteryLevel(lowBattery)
        }
    }

    func setAudioSessionActive(_ active: Bool) {
        queue.async { [weak self] in
            self?.isAudioSessionActive = active
            self?.audioDevice?.setManualAudioSessionIsActive(active)
        }
    }

    func setNetworkKind(_ networkKind: NetworkKind) {
        queue.async { [weak self] in
            self?.networkKind = networkKind
            self?.context?.setNetworkType(Self.networkType(for: networkKind))
        }
    }

    func stop(completion: (@Sendable (StopResult?) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else {
                completion?(nil)
                return
            }
            stopLocked(clearPendingSignaling: true, completion: completion)
        }
    }

    // MARK: Private

    private struct DebugInformation: Encodable {
        struct Traffic: Encodable {
            let receivedMobile: Int64
            let receivedWifi: Int64
            let sentMobile: Int64
            let sentWifi: Int64
        }

        let diagnostics: [String]
        let traffic: Traffic
        let version = 1
    }

    private let queue = DispatchQueue(label: "com.gruiachiscop.BetterTG.call-engine")
    private let contextQueue: CallContextQueue
    private var context: OngoingCallThreadLocalContextWebrtc?
    private var audioDevice: SharedCallAudioDevice?
    private var pendingSignaling = [Data]()
    private var generation = UUID()
    private var isMuted = false
    private var isLowBattery = false
    private var isAudioSessionActive = false
    private var networkKind = NetworkKind.wifi

    private static func networkType(for kind: NetworkKind) -> OngoingCallNetworkTypeWebrtc {
        switch kind {
        case .wifi: .wifi
        case .cellular: .cellularLte
        }
    }

    private static func state(from state: OngoingCallStateWebrtc) -> State {
        switch state {
        case .initializing: .initializing
        case .connected: .connected
        case .failed: .failed
        case .reconnecting: .reconnecting
        @unknown default: .unknown(state.rawValue)
        }
    }

    private static func diagnosticLines(from debugLog: String) -> [Substring] {
        let keywords = [
            "audio", "candidate", "connection", "delay", "ice", "jitter", "loss", "packet", "relay", "rtt", "turn",
        ]
        return debugLog
            .split(separator: "\n")
            .filter { line in
                let lowercaseLine = line.lowercased()
                return keywords.contains { lowercaseLine.contains($0) }
            }
            .suffix(200)
    }

    /// The server-requested payload needs the actual tail of the native log, not the narrower
    /// console filter above. Bound both line count and encoded size so termination stays cheap.
    private static func uploadedDebugLines(from debugLog: String) -> [String] {
        let boundedTail = String(debugLog.suffix(64000))
        return boundedTail.split(separator: "\n").suffix(400).map(String.init)
    }

    private static func stopResult(
        debugLog: String?,
        sentWifi: Int64,
        receivedWifi: Int64,
        sentMobile: Int64,
        receivedMobile: Int64,
    ) -> StopResult {
        let payload = DebugInformation(
            diagnostics: debugLog.map(uploadedDebugLines(from:)) ?? [],
            traffic: .init(
                receivedMobile: receivedMobile,
                receivedWifi: receivedWifi,
                sentMobile: sentMobile,
                sentWifi: sentWifi,
            ),
        )
        let encodedPayload = try? JSONEncoder().encode(payload)
        let debugInformation = encodedPayload.flatMap { String(data: $0, encoding: .utf8) }
        return StopResult(callLog: debugLog, debugInformation: debugInformation)
    }

    private func stopLocked(
        clearPendingSignaling: Bool,
        completion: (@Sendable (StopResult?) -> Void)? = nil,
    ) {
        generation = UUID()
        if let context {
            context.beginTermination()
            // Retain the native context until its asynchronous stop callback completes. Besides
            // making teardown deterministic, the final tgcalls log is the only available source
            // for ICE route, jitter and packet-loss diagnostics in protocol v8.
            context.stop { [context] debugLog, sentWifi, receivedWifi, sentMobile, receivedMobile in
                print(
                    "[Call][tgcalls] traffic wifi=\(sentWifi)/\(receivedWifi) mobile=\(sentMobile)/\(receivedMobile)",
                )
                if let debugLog {
                    let lines = Self.diagnosticLines(from: debugLog)
                    if !lines.isEmpty {
                        print("[Call][tgcalls] diagnostics:\n\(lines.joined(separator: "\n"))")
                    }
                }
                completion?(
                    Self.stopResult(
                        debugLog: debugLog,
                        sentWifi: sentWifi,
                        receivedWifi: receivedWifi,
                        sentMobile: sentMobile,
                        receivedMobile: receivedMobile,
                    ),
                )
                _ = context
            }
        } else {
            completion?(nil)
        }
        context = nil
        audioDevice?.setManualAudioSessionIsActive(false)
        audioDevice = nil
        if clearPendingSignaling {
            pendingSignaling.removeAll(keepingCapacity: false)
        }
    }
}
