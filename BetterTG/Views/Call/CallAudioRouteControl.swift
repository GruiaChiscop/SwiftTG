// CallAudioRouteControl.swift

import SwiftUI

// MARK: - CallAudioRouteControl

struct CallAudioRouteControl: View {
    // MARK: Internal

    let routes: [TelegramCallSession.AudioRoute]
    let selectedRoute: TelegramCallSession.AudioRoute
    let select: (TelegramCallSession.AudioRoute) -> Void

    var body: some View {
        if canToggleSpeakerDirectly {
            Button(action: toggleSpeaker) {
                CallAudioRouteLabel(
                    systemImage: Self.systemImage(for: selectedRoute.kind),
                    title: "Speaker",
                    isActive: selectedRoute.kind == .speaker,
                )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selectedRoute.kind == .speaker ? .isSelected : [])
        } else {
            Menu {
                ForEach(routes) { route in
                    Button {
                        select(route)
                    } label: {
                        Label(
                            route.name,
                            systemImage: route == selectedRoute
                                ? "checkmark"
                                : Self.systemImage(for: route.kind),
                        )
                    }
                }
            } label: {
                CallAudioRouteLabel(
                    systemImage: Self.systemImage(for: selectedRoute.kind),
                    title: "Audio",
                    isActive: selectedRoute.kind != .builtIn,
                )
            }
            .accessibilityValue(selectedRoute.name)
        }
    }

    // MARK: Private

    private var canToggleSpeakerDirectly: Bool {
        routes.contains(where: { $0.kind == .builtIn })
            && routes.contains(where: { $0.kind == .speaker })
            && routes.allSatisfy { $0.kind == .builtIn || $0.kind == .speaker }
    }

    private static func systemImage(for kind: TelegramCallSession.AudioRoute.Kind) -> String {
        switch kind {
        case .builtIn:
            "iphone"
        case .speaker:
            "speaker.wave.2.fill"
        case .wired:
            "headphones"
        case .bluetooth:
            "wave.3.right"
        case .external:
            "airplayaudio"
        }
    }

    private func toggleSpeaker() {
        let targetKind: TelegramCallSession.AudioRoute.Kind = selectedRoute.kind == .speaker ? .builtIn : .speaker
        guard let targetRoute = routes.first(where: { $0.kind == targetKind }) else { return }
        select(targetRoute)
    }
}
