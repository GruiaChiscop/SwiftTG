// TelegramCallSignalingConnection.swift

import Foundation
import Network

// MARK: - TelegramCallSignalingConnectionManager

/// Telegram's legacy (pre-v12) signaling fallback over the TCP reflector. Every method is called
/// on the call engine queue; `NWConnection` is started on that same queue.
final class TelegramCallSignalingConnectionManager {
    // MARK: Lifecycle

    init(
        queue: DispatchQueue,
        host: String,
        port: UInt16,
        peerTag: Data,
        dataReceived: @escaping (Data) -> Void,
    ) {
        self.queue = queue
        self.host = host
        self.port = port
        self.peerTag = peerTag
        self.dataReceived = dataReceived
    }

    // MARK: Internal

    func start() {
        guard !isRunning else { return }
        isRunning = true
        spawnConnection()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        connection?.stop()
        connection = nil
    }

    func send(_ payload: Data) {
        connection?.send(payload)
    }

    // MARK: Private

    private let queue: DispatchQueue
    private let host: String
    private let port: UInt16
    private let peerTag: Data
    private let dataReceived: (Data) -> Void
    private var connection: TelegramCallSignalingConnection?
    private var isRunning = false

    private func spawnConnection() {
        guard isRunning else { return }
        let connection = TelegramCallSignalingConnection(
            queue: queue,
            host: host,
            port: port,
            peerTag: peerTag,
            dataReceived: dataReceived,
            closed: { [weak self] in
                guard let self, isRunning else { return }
                self.connection = nil
                spawnConnection()
            },
        )
        self.connection = connection
        connection.start()
    }
}

// MARK: - TelegramCallSignalingConnection

/// `NWConnection` and every mutable field are confined to `queue`; Network.framework invokes all
/// handlers on that same queue. The annotation documents that queue-based synchronization.
private final class TelegramCallSignalingConnection: @unchecked Sendable {
    // MARK: Lifecycle

    init(
        queue: DispatchQueue,
        host: String,
        port: UInt16,
        peerTag: Data,
        dataReceived: @escaping (Data) -> Void,
        closed: @escaping () -> Void,
    ) {
        self.queue = queue
        self.peerTag = peerTag
        self.dataReceived = dataReceived
        self.closed = closed
        self.connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp,
        )
        connection.stateUpdateHandler = { [weak self] state in
            self?.handle(state)
        }
    }

    // MARK: Internal

    func start() {
        connection.start(queue: queue)
        receivePacketHeader()
    }

    func stop() {
        guard !isClosed else { return }
        isClosed = true
        pingTimer?.cancel()
        pingTimer = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
    }

    func send(_ payload: Data) {
        if isConnected {
            sendPacket(payload)
        } else {
            queuedPayloads.append(payload)
        }
    }

    // MARK: Private

    private let queue: DispatchQueue
    private let peerTag: Data
    private let dataReceived: (Data) -> Void
    private let closed: () -> Void
    private let connection: NWConnection
    private var isConnected = false
    private var isClosed = false
    private var pingTimer: DispatchSourceTimer?
    private var queuedPayloads = [Data]()

    private static func uint32(from data: Data) -> UInt32 {
        var value = UInt32.zero
        _ = withUnsafeMutableBytes(of: &value) { destination in
            data.copyBytes(to: destination)
        }
        return UInt32(littleEndian: value)
    }

    private func handle(_ state: NWConnection.State) {
        guard !isClosed else { return }
        switch state {
        case .ready:
            var header = UInt32(0xEEEE_EEEE).littleEndian
            connection.send(
                content: Data(bytes: &header, count: MemoryLayout<UInt32>.size),
                completion: .contentProcessed { [weak self] error in
                    if error != nil {
                        self?.close()
                    }
                },
            )
            schedulePing(every: .milliseconds(150))
            sendPacket(Data())
        case .cancelled, .failed:
            close()
        default:
            break
        }
    }

    private func schedulePing(every interval: DispatchTimeInterval) {
        pingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.sendPacket(Data())
        }
        pingTimer = timer
        timer.resume()
    }

    private func receivePacketHeader() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self, !isClosed else { return }
            guard error == nil, let data, data.count == 4 else {
                close()
                return
            }
            let payloadSize = Self.uint32(from: data)
            guard payloadSize < 2 * 1024 * 1024 else {
                close()
                return
            }
            receivePacketPayload(size: Int(payloadSize))
        }
    }

    private func receivePacketPayload(size: Int) {
        connection.receive(minimumIncompleteLength: size, maximumLength: size) { [weak self] data, _, _, error in
            guard let self, !isClosed else { return }
            guard error == nil, let data, data.count == size, data.count >= 20 else {
                close()
                return
            }
            guard data.prefix(16) == peerTag else {
                close()
                return
            }
            let actualPayloadSize = Int(Self.uint32(from: data.subdata(in: 16..<20)))
            guard actualPayloadSize <= data.count - 20 else {
                close()
                return
            }

            if !isConnected {
                isConnected = true
                schedulePing(every: .seconds(2))
                let queuedPayloads = queuedPayloads
                self.queuedPayloads.removeAll(keepingCapacity: true)
                for payload in queuedPayloads {
                    sendPacket(payload)
                }
            }
            if actualPayloadSize > 0 {
                dataReceived(data.subdata(in: 20..<(20 + actualPayloadSize)))
            }
            receivePacketHeader()
        }
    }

    private func sendPacket(_ payload: Data) {
        guard !isClosed else { return }
        let cleanSize = 20 + payload.count
        let paddingSize = (4 - cleanSize % 4) % 4
        var totalSize = UInt32(cleanSize + paddingSize).littleEndian
        var payloadSize = UInt32(payload.count).littleEndian
        var packet = Data(bytes: &totalSize, count: 4)
        packet.append(peerTag)
        packet.append(Data(bytes: &payloadSize, count: 4))
        packet.append(payload)
        if paddingSize > 0 {
            packet.append(Data(repeating: 0, count: paddingSize))
        }
        connection.send(content: packet, isComplete: true, completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.close()
            }
        })
    }

    private func close() {
        guard !isClosed else { return }
        stop()
        closed()
    }
}
