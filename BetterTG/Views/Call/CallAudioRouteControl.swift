// CallAudioRouteControl.swift

import SwiftUI

// MARK: - CallAudioRouteControl

struct CallAudioRouteControl: View {
    // MARK: Internal

    let routes: [TelegramCallSession.AudioRoute]
    let selectedRoute: TelegramCallSession.AudioRoute
    let select: (TelegramCallSession.AudioRoute) -> Void

    var body: some View {
        Menu {
            ForEach(routes) { route in
                Button {
                    select(route)
                } label: {
                    Label(
                        route.name,
                        systemImage: route == selectedRoute ? "checkmark" : Self.systemImage(for: route.kind),
                    )
                }
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: Self.systemImage(for: selectedRoute.kind))
                    .font(.title2)
                    .frame(width: 64, height: 64)
                    .background(controlBackground, in: .circle)
                    .foregroundStyle(controlForeground)

                Text("Audio")
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityValue(selectedRoute.name)
    }

    // MARK: Private

    private var controlBackground: Color {
        selectedRoute.kind == .speaker ? .white : .white.opacity(0.16)
    }

    private var controlForeground: Color {
        selectedRoute.kind == .speaker ? .black : .white
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
}
