// TDLib.swift

import Combine
import SwiftUI
import TDLibKit

// MARK: - TDLib

final class TDLib: @unchecked Sendable {
    // MARK: Lifecycle

    private init() {
        self.session = TelegramSession()
    }

    // MARK: Internal

    static let shared = TDLib()

    var authorizationStatePublisher: AnyPublisher<AuthorizationState, Never> {
        session.authorizationStatePublisher
    }

    var service: any TelegramService { session }

    func startTdLibUpdateHandler() {
        let dir = try? FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "td")
            .path()
        guard let dir else { return }
        session.start(configuration: .init(
            apiHash: Secret.apiHash,
            apiId: Secret.apiId,
            applicationVersion: Utils.applicationVersion,
            databaseDirectory: dir,
            deviceModel: Utils.modelName,
            systemLanguageCode: "en-US",
            systemVersion: UIDevice.current.systemVersion,
        ))

        nc.publisher(&cancellables, for: UIApplication.willTerminateNotification) { [weak self] _ in
            self?.session.close()
        }
    }

    // MARK: Private

    private var cancellables = Set<AnyCancellable>()
    private let session: TelegramSession
}
