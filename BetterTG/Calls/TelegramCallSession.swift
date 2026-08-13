// TelegramCallSession.swift

import AVFoundation
import Combine
import Observation
import TDLibKit
import TgVoipWebrtc

/// TDLibKit's generated models don't declare `Sendable`; `CallProtocol` is a plain value type of
/// trivially-Sendable fields (Bool/Int/[String]), and needs to cross the actor boundary from this
/// `@MainActor` class into `TelegramService`'s nonisolated async RPC methods.
extension CallProtocol: @retroactive @unchecked Sendable {}

/// Bridges TDLib's call signaling (`Call`/`CallState`, driven entirely by TDLib itself - including
/// the Diffie-Hellman key exchange, so this type never touches raw call crypto) to the vendored
/// tgcalls engine (`Vendor/TgVoipWebrtc`). iOS-only for now, since the vendored engine is - see
/// `Vendor/TgVoipWebrtc/ORIGIN.md`.
///
/// Phase 1 scope: audio-only, 1:1 calls. No video capturer, no proxy, no direct-connection
/// shortcut, no TCP-signaling-reflector fallback - TDLib's own `sendCallSignalingData`/
/// `updateNewCallSignalingData` round trip through Telegram's servers is the only signaling
/// transport, which is simpler than Telegram-iOS's own `OngoingCallContext` (which layers an
/// additional raw-socket-to-reflector path on top, as a latency optimization, not a correctness
/// requirement) and correct on its own.
@MainActor
@Observable final class TelegramCallSession {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
        service.callPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] call in self?.handle(call: call) }
            .store(in: &cancellables)
        service.callSignalingDataPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.handleSignaling(data) }
            .store(in: &cancellables)
    }

    // MARK: Internal

    static let shared = TelegramCallSession(service: TDLib.shared.service)

    private(set) var activeCall: Call?
    private(set) var engineState: OngoingCallStateWebrtc?
    private(set) var isMuted = false

    func startCall(userId: Int64) {
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await service.createCall(isVideo: false, protocol: Self.ourProtocol(), userId: userId)
            } catch {
                log("Error creating call: \(error)")
            }
        }
    }

    func answer() {
        guard let activeCall else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await service.acceptCall(callId: activeCall.id, protocol: Self.ourProtocol())
            } catch {
                log("Error accepting call: \(error)")
            }
        }
    }

    func end() {
        guard let activeCall else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await service.discardCall(
                    callId: activeCall.id,
                    connectionId: 0,
                    duration: 0,
                    inviteLink: nil,
                    isDisconnected: false,
                    isVideo: activeCall.isVideo,
                )
            } catch {
                log("Error discarding call: \(error)")
            }
        }
    }

    func toggleMute() {
        isMuted.toggle()
        engineContext?.setIsMuted(isMuted)
    }

    // MARK: Private

    private static let engineQueue = DispatchQueue(label: "com.gruiachiscop.BetterTG.call-engine")

    private let service: any TelegramService
    private var cancellables = Set<AnyCancellable>()
    private var engineContext: OngoingCallThreadLocalContextWebrtc?
    private var audioDevice: SharedCallAudioDevice?
    private var contextQueue: CallContextQueue?

    private static func ourProtocol() -> CallProtocol {
        CallProtocol(
            libraryVersions: OngoingCallThreadLocalContextWebrtc.versions(withIncludeReference: false),
            maxLayer: Int(OngoingCallThreadLocalContextWebrtc.maxLayer()),
            minLayer: 65,
            udpP2p: true,
            udpReflector: true,
        )
    }

    private func handle(call: Call?) {
        guard let call else {
            activeCall = nil
            stopEngine()
            return
        }
        activeCall = call
        switch call.state {
        case .callStateReady(let info):
            startEngine(call: call, info: info)
        case .callStateDiscarded, .callStateError:
            activeCall = nil
            stopEngine()
        default:
            break
        }
    }

    private func handleSignaling(_ data: UpdateNewCallSignalingData) {
        guard data.callId == activeCall?.id else { return }
        engineContext?.addSignaling(data.data)
    }

    private func startEngine(call: Call, info: CallStateReady) {
        guard engineContext == nil else { return }
        guard let version = Self.pickVersion(from: info.protocol.libraryVersions) else {
            log("No mutually supported call protocol version")
            return
        }

        SharedCallAudioDevice.setupAudioSession()
        let audioDevice = SharedCallAudioDevice(disableRecording: false, enableSystemMute: false)
        self.audioDevice = audioDevice

        let queue = CallContextQueue(queue: Self.engineQueue)
        contextQueue = queue

        let context = OngoingCallThreadLocalContextWebrtc(
            version: version,
            customParameters: info.customParameters.isEmpty ? nil : info.customParameters,
            queue: queue,
            proxy: nil,
            networkType: .wifi,
            dataSaving: .never,
            derivedState: Data(),
            key: info.encryptionKey,
            isOutgoing: call.isOutgoing,
            connections: Self.connections(from: info.servers),
            maxLayer: Int32(info.protocol.maxLayer),
            allowP2P: info.allowP2p,
            allowTCP: true,
            enableStunMarking: true,
            logPath: "",
            statsLogPath: "",
            sendSignalingData: { [weak self] data in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    _ = try? await service.sendCallSignalingData(callId: call.id, data: data)
                }
            },
            videoCapturer: nil,
            preferredVideoCodec: nil,
            audioInputDeviceId: "",
            audioDevice: audioDevice,
            directConnection: nil,
        )
        context.stateChanged = { [weak self] state, _, _, _, _, _ in
            Task { @MainActor [weak self] in self?.engineState = state }
        }
        engineContext = context
        audioDevice.setManualAudioSessionIsActive(true)
    }

    private func stopEngine() {
        guard let engineContext else { return }
        engineContext.beginTermination()
        engineContext.stop(nil)
        self.engineContext = nil
        engineState = nil
        isMuted = false
        audioDevice?.setManualAudioSessionIsActive(false)
        audioDevice = nil
        contextQueue = nil
    }

    /// Highest version both sides support - `libraryVersions` lists are small (a handful of dotted
    /// version strings like "12.0.0"), so a straightforward numeric-component comparison is enough;
    /// no need for a general semver library.
    private static func pickVersion(from theirVersions: [String]) -> String? {
        let ours = Set(OngoingCallThreadLocalContextWebrtc.versions(withIncludeReference: false))
        let mutual = theirVersions.filter(ours.contains)
        return mutual.max { compareVersions($0, $1) < 0 }
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(left.count, right.count) {
            let leftComponent = index < left.count ? left[index] : 0
            let rightComponent = index < right.count ? right[index] : 0
            if leftComponent != rightComponent {
                return leftComponent - rightComponent
            }
        }
        return 0
    }

    /// Mirrors Telegram-iOS's own `OngoingCallContext.callConnectionDescriptionsWebrtc`: reflector
    /// servers get a small sequential id (sorted by TDLib's server id, 1-based) that the engine uses
    /// to pick a primary relay, one connection description per IP family present; WebRTC servers
    /// always use reflector id 0 and carry their own username/password instead of a peer tag.
    private static func connections(from servers: [CallServer]) -> [OngoingCallConnectionDescriptionWebrtc] {
        let reflectorIds = servers
            .compactMap { server -> TdInt64? in
                guard case .callServerTypeTelegramReflector = server.type else { return nil }
                return server.id
            }
            .sorted()
        let reflectorIdMapping = Dictionary(uniqueKeysWithValues: reflectorIds.enumerated().map { ($1, UInt8($0 + 1)) })

        return servers.flatMap { server -> [OngoingCallConnectionDescriptionWebrtc] in
            switch server.type {
            case .callServerTypeTelegramReflector(let reflector):
                guard let reflectorId = reflectorIdMapping[server.id] else { return [] }
                return [server.ipAddress, server.ipv6Address].filter { !$0.isEmpty }.map { ip in
                    OngoingCallConnectionDescriptionWebrtc(
                        reflectorId: reflectorId,
                        hasStun: false,
                        hasTurn: true,
                        hasTcp: reflector.isTcp,
                        ip: ip,
                        port: Int32(server.port),
                        username: "reflector",
                        password: reflector.peerTag.map { String(format: "%02x", $0) }.joined(),
                    )
                }
            case .callServerTypeWebrtc(let webrtc):
                return [server.ipAddress, server.ipv6Address].filter { !$0.isEmpty }.map { ip in
                    OngoingCallConnectionDescriptionWebrtc(
                        reflectorId: 0,
                        hasStun: webrtc.supportsStun,
                        hasTurn: webrtc.supportsTurn,
                        hasTcp: false,
                        ip: ip,
                        port: Int32(server.port),
                        username: webrtc.username,
                        password: webrtc.password,
                    )
                }
            }
        }
    }
}
