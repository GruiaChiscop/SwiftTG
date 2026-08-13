// TelegramCallSession.swift

import AVFoundation
import Combine
import Network
import Observation
import TDLibKit
@preconcurrency import TgVoipWebrtc
import UIKit

// MARK: - CallProtocol + @retroactive @unchecked Sendable

/// TDLibKit's generated models don't declare `Sendable`; `CallProtocol` is a value made entirely
/// from Sendable fields and crosses the actor boundary into TelegramService's async RPC methods.
extension CallProtocol: @retroactive @unchecked Sendable {}

// MARK: - TelegramCallSession

/// Bridges TDLib's call state/signaling to the vendored tgcalls engine. The first implementation is
/// intentionally audio-only; TelegramCallEngine owns the strict tgcalls queue confinement.
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
        CallKitManager.shared
            .audioSessionActivePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in self?.applyAudioSessionActive(active) }
            .store(in: &cancellables)

        let notificationCenter = NotificationCenter.default
        notificationCenter.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.handleAudioRouteChange(notification) }
            .store(in: &cancellables)
        notificationCenter.publisher(for: AVAudioSession.availableInputsChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshAudioRoutes() }
            .store(in: &cancellables)
        notificationCenter.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.handleAudioInterruption(notification) }
            .store(in: &cancellables)
        notificationCenter.publisher(for: AVAudioSession.mediaServicesWereLostNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleMediaServicesLost() }
            .store(in: &cancellables)
        notificationCenter.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleMediaServicesReset() }
            .store(in: &cancellables)

        refreshAudioRoutes()

        networkMonitor.pathUpdateHandler = { [weak self] path in
            let kind: TelegramCallEngine.NetworkKind = path.usesInterfaceType(.cellular) ? .cellular : .wifi
            Task { @MainActor [weak self] in
                self?.applyNetworkKind(kind)
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    // MARK: Internal

    struct AudioRoute: Identifiable, Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case builtIn
            case speaker
            case wired
            case bluetooth
            case external
        }

        static let builtIn = AudioRoute(id: "builtin", name: "iPhone", kind: .builtIn)
        static let speaker = AudioRoute(id: "speaker", name: "Speaker", kind: .speaker)

        let id: String
        let name: String
        let kind: Kind
    }

    static let shared = TelegramCallSession(service: TDLib.shared.service)

    private(set) var activeCall: Call?

    private(set) var engineState: TelegramCallEngine.State?
    private(set) var isMuted = false
    private(set) var isSpeakerOn = false
    private(set) var availableAudioRoutes: [AudioRoute] = [.builtIn, .speaker]
    private(set) var selectedAudioRoute = AudioRoute.builtIn
    private(set) var connectedAt: Foundation.Date?

    var onIncomingCall: ((Call) -> Void)?
    var onCallConnected: (() -> Void)?
    var onCallEnded: (() -> Void)?

    /// The native CallKit UI remains the sole incoming-answer surface while the call is pending.
    var shouldShowCallView: Bool {
        guard let activeCall else { return false }
        if !activeCall.isOutgoing, case .callStatePending = activeCall.state {
            return false
        }
        return true
    }

    /// tgcalls configures the category/mode/options CallKit will later activate. This has to run
    /// before reporting or requesting a CallKit call, matching Telegram-iOS's ordering.
    static func prepareAudioSession() {
        SharedCallAudioDevice.setupAudioSession()
    }

    func startCall(userId: Int64, completion: @escaping (Bool) -> Void = { _ in }) {
        Task { [weak self] in
            guard let self else {
                completion(false)
                return
            }
            do {
                _ = try await service.createCall(isVideo: false, protocol: Self.ourProtocol(), userId: userId)
                completion(true)
            } catch {
                log("Error creating call: \(error)")
                completion(false)
            }
        }
    }

    func answer() {
        answerActiveCall()
    }

    /// CallKit can deliver Answer before TDLib publishes the call after a cold VoIP wake. Keep the
    /// action and apply it to the first real call rather than fulfilling and losing it.
    func answerFromSystem() {
        guard activeCall != nil else {
            pendingSystemAction = .answer
            log("[Call] deferring system Answer until TDLib publishes the call")
            return
        }
        answerActiveCall()
    }

    func end() {
        endActiveCall(isDisconnected: false)
    }

    /// The same cold-wake race applies to End; End takes precedence over an earlier Answer.
    func endFromSystem() {
        guard activeCall != nil else {
            pendingSystemAction = .end
            log("[Call] deferring system End until TDLib publishes the call")
            return
        }
        endActiveCall(isDisconnected: false)
    }

    func cancelPendingSystemAction() {
        pendingSystemAction = nil
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        engine.setMuted(muted)
    }

    func toggleSpeaker() {
        selectAudioRoute(isSpeakerOn ? .builtIn : .speaker)
    }

    func selectAudioRoute(_ route: AudioRoute) {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            switch route.kind {
            case .speaker:
                if let builtInMicrophone = audioSession.availableInputs?.first(where: {
                    $0.portType == .builtInMic
                }) {
                    try audioSession.setPreferredInput(builtInMicrophone)
                }
                try audioSession.overrideOutputAudioPort(.speaker)
            case .builtIn:
                try audioSession.overrideOutputAudioPort(.none)
                let builtInMicrophone = audioSession.availableInputs?.first(where: {
                    $0.portType == .builtInMic
                })
                try audioSession.setPreferredInput(builtInMicrophone)
            case .bluetooth, .external, .wired:
                try audioSession.overrideOutputAudioPort(.none)
                guard let input = audioSession.availableInputs?.first(where: {
                    Self.audioRouteId(for: $0) == route.id
                }) else {
                    refreshAudioRoutes()
                    return
                }
                try audioSession.setPreferredInput(input)
            }
            refreshAudioRoutes()
        } catch {
            log("Error selecting call audio route \(route.name): \(error)")
            refreshAudioRoutes()
        }
    }

    // MARK: Private

    private enum PendingSystemAction {
        case answer
        case end
    }

    private let service: any TelegramService
    private let engine = TelegramCallEngine()
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "com.gruiachiscop.BetterTG.call-network")
    private var cancellables = Set<AnyCancellable>()
    private var reportedIncomingCallId: Int?
    private var ringbackAudioDevice: SharedCallAudioDevice?
    private var isCallKitAudioSessionActive = false
    private var isEffectiveAudioSessionActive = false
    private var isAudioInterrupted = false
    private var areMediaServicesAvailable = true
    private var ownsProximityMonitoring = false
    private var isEngineRunning = false
    private var networkKind = TelegramCallEngine.NetworkKind.wifi
    private var pendingSystemAction: PendingSystemAction?
    private var isAnswering = false
    private var isEnding = false

    private static func ourProtocol() -> CallProtocol {
        CallProtocol(
            libraryVersions: OngoingCallThreadLocalContextWebrtc.versions(withIncludeReference: false),
            maxLayer: Int(OngoingCallThreadLocalContextWebrtc.maxLayer()),
            minLayer: 65,
            udpP2p: true,
            udpReflector: true,
        )
    }

    private static func ringbackTone() -> CallAudioTone {
        let sampleRate = 48000
        let onDuration = 1.0
        let offDuration = 3.0
        let totalSamples = Int((onDuration + offDuration) * Double(sampleRate))
        let onSamples = Int(onDuration * Double(sampleRate))
        var samples = [Int16](repeating: 0, count: totalSamples)
        let amplitude = 0.2 * Double(Int16.max)
        for index in 0..<onSamples {
            let phase = 2.0 * Double.pi * 440.0 * Double(index) / Double(sampleRate)
            samples[index] = Int16(sin(phase) * amplitude)
        }
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        return CallAudioTone(samples: data, sampleRate: sampleRate, loopCount: 1_000_000)
    }

    /// Telegram negotiates by taking the first remote version also present locally. Choosing the
    /// numerically-highest mutual version can make each peer select a different protocol.
    private static func pickVersion(from theirVersions: [String]) -> String? {
        let ours = Set(OngoingCallThreadLocalContextWebrtc.versions(withIncludeReference: false))
        return theirVersions.first(where: ours.contains)
    }

    private static func isTerminal(_ state: CallState) -> Bool {
        switch state {
        case .callStateDiscarded, .callStateError: true
        default: false
        }
    }

    private static func describe(_ state: CallState) -> String {
        switch state {
        case .callStatePending(let value):
            "pending(isCreated=\(value.isCreated) isReceived=\(value.isReceived))"
        case .callStateExchangingKeys:
            "exchangingKeys"
        case .callStateReady(let value):
            "ready(allowP2p=\(value.allowP2p) servers=\(value.servers.count) protocolVersions=\(value.protocol.libraryVersions.joined(separator: ",")))"
        case .callStateHangingUp:
            "hangingUp"
        case .callStateDiscarded(let value):
            "discarded(reason=\(value.reason) needRating=\(value.needRating) needDebugInformation=\(value.needDebugInformation))"
        case .callStateError(let value):
            "error(code=\(value.error.code) message=\(value.error.message))"
        }
    }

    private static func describe(engineState: TelegramCallEngine.State) -> String {
        switch engineState {
        case .initializing: "initializing"
        case .connected: "connected"
        case .failed: "failed"
        case .reconnecting: "reconnecting"
        case .unknown(let rawValue): "unknown(\(rawValue))"
        }
    }

    private static func audioRouteId(for port: AVAudioSessionPortDescription) -> String {
        "port:\(port.uid)"
    }

    private static func audioRouteKind(for portType: AVAudioSession.Port) -> AudioRoute.Kind {
        switch portType {
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            .bluetooth
        case .headphones, .headsetMic, .lineIn:
            .wired
        default:
            .external
        }
    }

    private static func audioRoute(for port: AVAudioSessionPortDescription) -> AudioRoute {
        AudioRoute(
            id: audioRouteId(for: port),
            name: port.portName,
            kind: audioRouteKind(for: port.portType),
        )
    }

    private static func connections(from servers: [CallServer]) -> [TelegramCallEngine.Connection] {
        let reflectorIds = servers
            .compactMap { server -> TdInt64? in
                guard case .callServerTypeTelegramReflector = server.type else { return nil }
                return server.id
            }
            .sorted()
        let mapping = Dictionary(uniqueKeysWithValues: reflectorIds.enumerated().map { ($1, UInt8($0 + 1)) })

        return servers.flatMap { server -> [TelegramCallEngine.Connection] in
            switch server.type {
            case .callServerTypeTelegramReflector(let reflector):
                guard let reflectorId = mapping[server.id] else { return [] }
                return [server.ipAddress, server.ipv6Address].filter { !$0.isEmpty }.map { ip in
                    .init(
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
                    .init(
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

    private func handle(call: Call?) {
        guard let call else {
            // `callPublisher` starts with nil. It is not an ended call and must not dismiss a fresh
            // CallKit placeholder or erase an Answer/End action received during a cold launch.
            guard activeCall != nil || reportedIncomingCallId != nil || isEngineRunning else { return }
            finishCurrentCall(notifyCallKit: true)
            return
        }

        log("[Call] id=\(call.id) isOutgoing=\(call.isOutgoing) state=\(Self.describe(call.state))")
        if Self.isTerminal(call.state) {
            // A terminal update can be TDLib's first update after a VoIP placeholder. Count it as
            // a real call so CallKit is dismissed, but never report it as a fresh incoming call.
            activeCall = call
            finishCurrentCall(notifyCallKit: true)
            return
        }

        if let current = activeCall, current.id != call.id {
            stopRingback()
            stopEngine()
            reportedIncomingCallId = nil
        }
        activeCall = call
        updateProximityMonitoring()

        if pendingSystemAction == .end {
            pendingSystemAction = nil
            endActiveCall(isDisconnected: false)
            return
        }

        if !call.isOutgoing, reportedIncomingCallId != call.id {
            reportedIncomingCallId = call.id
            onIncomingCall?(call)
        }

        if pendingSystemAction == .answer {
            pendingSystemAction = nil
            answerActiveCall()
        }

        switch call.state {
        case .callStatePending:
            if call.isOutgoing {
                startRingback()
            }
        case .callStateReady(let info):
            stopRingback()
            startEngine(call: call, info: info)
        default:
            break
        }
    }

    private func answerActiveCall() {
        guard let call = activeCall else {
            log("[Call] answer() called with no activeCall")
            return
        }
        guard !isAnswering else { return }
        isAnswering = true
        log("[Call] accepting callId=\(call.id)")
        Task { [weak self] in
            guard let self else { return }
            defer { isAnswering = false }
            do {
                _ = try await service.acceptCall(callId: call.id, protocol: Self.ourProtocol())
                log("[Call] acceptCall RPC succeeded for callId=\(call.id)")
            } catch {
                log("Error accepting call: \(error)")
                endActiveCall(isDisconnected: true)
            }
        }
    }

    private func endActiveCall(isDisconnected: Bool) {
        guard let call = activeCall else { return }
        guard !isEnding else { return }
        isEnding = true
        let duration = connectedAt.map { max(0, Int(Foundation.Date().timeIntervalSince($0))) } ?? 0
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await service.discardCall(
                    callId: call.id,
                    connectionId: 0,
                    duration: duration,
                    inviteLink: nil,
                    isDisconnected: isDisconnected,
                    isVideo: call.isVideo,
                )
            } catch {
                log("Error discarding call: \(error)")
                finishCurrentCall(notifyCallKit: true)
            }
            isEnding = false
        }
    }

    private func startRingback() {
        guard ringbackAudioDevice == nil, !isEngineRunning else { return }
        let device = SharedCallAudioDevice(disableRecording: true, enableSystemMute: false)
        ringbackAudioDevice = device
        device.setTone(Self.ringbackTone())
        device.setManualAudioSessionIsActive(isEffectiveAudioSessionActive)
    }

    private func applyAudioSessionActive(_ active: Bool) {
        isCallKitAudioSessionActive = active
        applyEffectiveAudioSessionState()
        refreshAudioRoutes()
    }

    private func applyEffectiveAudioSessionState() {
        let active = isCallKitAudioSessionActive && !isAudioInterrupted && areMediaServicesAvailable
        guard active != isEffectiveAudioSessionActive else { return }
        isEffectiveAudioSessionActive = active
        log(
            "[Call] audio session effective=\(active) CallKit=\(isCallKitAudioSessionActive) interrupted=\(isAudioInterrupted) mediaServices=\(areMediaServicesAvailable)",
        )
        engine.setAudioSessionActive(active)
        ringbackAudioDevice?.setManualAudioSessionIsActive(active)
    }

    private func applyNetworkKind(_ kind: TelegramCallEngine.NetworkKind) {
        networkKind = kind
        engine.setNetworkKind(kind)
    }

    private func stopRingback() {
        guard let device = ringbackAudioDevice else { return }
        device.setTone(nil)
        device.setManualAudioSessionIsActive(false)
        ringbackAudioDevice = nil
    }

    private func handleSignaling(_ data: UpdateNewCallSignalingData) {
        guard data.callId == activeCall?.id else { return }
        engine.addSignaling(data.data)
    }

    private func startEngine(call: Call, info: CallStateReady) {
        guard !isEngineRunning else { return }
        guard let version = Self.pickVersion(from: info.protocol.libraryVersions) else {
            log("No mutually supported call protocol version")
            endActiveCall(isDisconnected: true)
            return
        }

        isEngineRunning = true
        let callId = call.id
        engine.start(
            configuration: .init(
                version: version,
                customParameters: info.customParameters.isEmpty ? nil : info.customParameters,
                encryptionKey: info.encryptionKey,
                isOutgoing: call.isOutgoing,
                connections: Self.connections(from: info.servers),
                maxLayer: Int32(info.protocol.maxLayer),
                allowP2P: info.allowP2p,
            ),
            muted: isMuted,
            audioSessionActive: isEffectiveAudioSessionActive,
            networkKind: networkKind,
            sendSignaling: { [weak self] data in
                Task { @MainActor [weak self] in
                    guard let self, activeCall?.id == callId else { return }
                    do {
                        _ = try await service.sendCallSignalingData(callId: callId, data: data)
                    } catch {
                        log("Error sending call signaling: \(error)")
                    }
                }
            },
            stateChanged: { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleEngineState(state, callId: callId)
                }
            },
        )
    }

    private func handleEngineState(_ state: TelegramCallEngine.State, callId: Int) {
        guard isEngineRunning, activeCall?.id == callId else { return }
        log("[Call] engine state=\(Self.describe(engineState: state))")
        engineState = state
        if connectedAt == nil, state == .connected {
            connectedAt = Foundation.Date()
            onCallConnected?()
        } else if state == .failed {
            endActiveCall(isDisconnected: true)
        }
    }

    private func handleAudioRouteChange(_ notification: Foundation.Notification) {
        let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
        refreshAudioRoutes()
        log(
            "[Call] audio route changed reason=\(reason.map(String.init) ?? "unknown") selected=\(selectedAudioRoute.name)",
        )
    }

    private func refreshAudioRoutes() {
        let audioSession = AVAudioSession.sharedInstance()
        var routes: [AudioRoute] = [.builtIn, .speaker]
        for input in audioSession.availableInputs ?? [] where input.portType != .builtInMic {
            let route = Self.audioRoute(for: input)
            if !routes.contains(where: { $0.id == route.id }) {
                routes.append(route)
            }
        }

        let currentRoute = audioSession.currentRoute
        let selected: AudioRoute =
            if currentRoute.outputs.contains(where: { $0.portType == .builtInSpeaker }) {
                .speaker
            } else if currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) {
                .builtIn
            } else if let input = currentRoute.inputs.first(where: { $0.portType != .builtInMic }) {
                Self.audioRoute(for: input)
            } else if let output = currentRoute.outputs.first(where: {
                $0.portType != .builtInReceiver && $0.portType != .builtInSpeaker
            }) {
                Self.audioRoute(for: output)
            } else {
                .builtIn
            }

        if !routes.contains(where: { $0.id == selected.id }) {
            routes.append(selected)
        }
        availableAudioRoutes = routes
        selectedAudioRoute = selected
        isSpeakerOn = selected.kind == .speaker
        updateProximityMonitoring()
    }

    /// Keep the display protected from accidental touches only while the receiver is the actual
    /// output. Speaker, wired, Bluetooth, and external routes must leave the screen awake. The
    /// ownership flag avoids disabling monitoring that another app component may have enabled.
    private func updateProximityMonitoring() {
        let shouldMonitor = activeCall != nil && selectedAudioRoute.kind == .builtIn
        if shouldMonitor, !ownsProximityMonitoring {
            UIDevice.current.isProximityMonitoringEnabled = true
            ownsProximityMonitoring = UIDevice.current.isProximityMonitoringEnabled
            log("[Call] proximity monitoring enabled=\(ownsProximityMonitoring)")
        } else if !shouldMonitor, ownsProximityMonitoring {
            UIDevice.current.isProximityMonitoringEnabled = false
            ownsProximityMonitoring = false
            log("[Call] proximity monitoring disabled")
        }
    }

    private func handleAudioInterruption(_ notification: Foundation.Notification) {
        guard
            let rawType = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        switch type {
        case .began:
            isAudioInterrupted = true
            log("[Call] audio interruption began")
        case .ended:
            isAudioInterrupted = false
            let rawOptions = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            log("[Call] audio interruption ended shouldResume=\(shouldResume)")
        @unknown default:
            return
        }
        applyEffectiveAudioSessionState()
        refreshAudioRoutes()
    }

    private func handleMediaServicesLost() {
        areMediaServicesAvailable = false
        log("[Call] audio media services lost")
        applyEffectiveAudioSessionState()
    }

    private func handleMediaServicesReset() {
        areMediaServicesAvailable = true
        log("[Call] audio media services reset")
        if activeCall != nil {
            Self.prepareAudioSession()
        }
        applyEffectiveAudioSessionState()
        refreshAudioRoutes()
    }

    private func stopEngine() {
        engine.stop()
        isEngineRunning = false
        engineState = nil
        isMuted = false
        connectedAt = nil
        if isSpeakerOn {
            do {
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
            } catch {
                log("Error restoring call audio route: \(error)")
            }
        }
        refreshAudioRoutes()
    }

    private func finishCurrentCall(notifyCallKit: Bool) {
        let hadCall = activeCall != nil || reportedIncomingCallId != nil || isEngineRunning
        activeCall = nil
        reportedIncomingCallId = nil
        pendingSystemAction = nil
        isAnswering = false
        isEnding = false
        stopRingback()
        stopEngine()
        if notifyCallKit, hadCall {
            onCallEnded?()
        }
    }
}
