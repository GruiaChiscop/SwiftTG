// NotificationCenter.swift

import Combine
import SwiftUI

let nc = NotificationCenter()
let updatesQueue = DispatchQueue(label: "updatesQueue", qos: .userInteractive)

extension NotificationCenter {
    func publisher(
        _ cancellables: inout Set<AnyCancellable>,
        for name: Notification.Name,
        _ perform: @escaping (Publisher.Output) -> Void,
    ) {
        publisher(for: name)
            .receive(on: updatesQueue)
            .sink { perform($0) }
            .store(in: &cancellables)
    }

    func post(name: Notification.Name) {
        post(name: name, object: nil)
    }

    func publisher(for name: Notification.Name) -> NotificationCenter.Publisher {
        publisher(for: name, object: nil)
    }
}
