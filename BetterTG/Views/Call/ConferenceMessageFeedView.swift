// ConferenceMessageFeedView.swift

import SwiftUI

// MARK: - ConferenceMessageFeedView

struct ConferenceMessageFeedView: View {
    // MARK: Internal

    let messages: [ConferenceMessagePresentation]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(messages) { message in
                        ConferenceMessageRow(message: message)
                            .id(message.id)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollIndicators(.hidden)
            .onChange(of: messages.last?.id) { _, messageId in
                guard let messageId else { return }
                proxy.scrollTo(messageId, anchor: .bottom)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: messages.map(\.id))
        }
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
}
