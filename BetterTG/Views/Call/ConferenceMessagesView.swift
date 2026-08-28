// ConferenceMessagesView.swift

import SwiftUI

// MARK: - ConferenceMessagesView

struct ConferenceMessagesView: View {
    // MARK: Internal

    let messages: [ConferenceMessagePresentation]
    let canSend: Bool
    let characterLimit: Int
    let send: (String) async -> Bool
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            ConferenceMessageFeedView(messages: messages)
                .frame(maxHeight: 280)

            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    canSend ? "Message" : "Messaging isn't available",
                    text: $draft,
                    axis: .vertical,
                )
                .lineLimit(1...4)
                .submitLabel(.send)
                .disabled(!canSend || sendTask != nil)
                .focused($isTextFieldFocused)
                .onSubmit(sendDraft)

                if sendTask != nil {
                    ProgressView()
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Sending message")
                } else {
                    Button("Send", systemImage: "arrow.up.circle.fill", action: sendDraft)
                        .labelStyle(.iconOnly)
                        .font(.title)
                        .frame(width: 44, height: 44)
                        .disabled(!canSubmit)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
        }
        .onAppear {
            isTextFieldFocused = canSend
        }
        .onChange(of: draft) { _, updatedDraft in
            guard updatedDraft.count > characterLimit else { return }
            draft = String(updatedDraft.prefix(characterLimit))
        }
        .onDisappear {
            sendTask?.cancel()
        }
        .accessibilityAction(.escape, dismiss)
        .alert("Message Not Sent", isPresented: $showsSendError) {
            Button("OK") {}
        } message: {
            Text("SwiftTG couldn't send this message. Please try again.")
        }
    }

    // MARK: Private

    @FocusState private var isTextFieldFocused: Bool
    @State private var draft = ""
    @State private var sendTask: Task<Void, Never>?
    @State private var showsSendError = false

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        canSend && sendTask == nil && !trimmedDraft.isEmpty
    }

    private func sendDraft() {
        guard canSubmit else { return }
        let submittedText = trimmedDraft
        sendTask = Task { @MainActor in
            let didSend = await send(submittedText)
            guard !Task.isCancelled else { return }
            if didSend {
                if trimmedDraft == submittedText {
                    draft = ""
                }
            } else {
                showsSendError = true
            }
            sendTask = nil
        }
    }
}
