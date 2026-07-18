// MacConversationView.swift

import AppKit
import SwiftUI

// MARK: - MacConversationView

struct MacConversationView: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let chat: ChatListItemState

    var body: some View {
        VStack(spacing: 0) {
            MacConversationHeader(
                title: chat.title,
                status: model.conversationHeaderStatus,
                onOpenInfo: { showsChatInfo = true },
            )
            Divider()
            messages
            Divider()
            if chat.kind != .channel || chat.canPostMessages == true {
                composer
            } else {
                Text("Only channel administrators can post.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .accessibilityLabel("Only channel administrators can post")
            }
        }
        .sheet(isPresented: $showsChatInfo) {
            MacChatInfoView(model: model, chat: chat)
        }
    }

    // MARK: Private

    @State private var selectedMessageId: Int64?
    @State private var isAtBottom = false
    @State private var showsChatInfo = false

    private var shouldFollowLatestMessage: Bool {
        switch model.messages.change {
        case .newMessage(let update):
            isAtBottom || update.message.isOutgoing
        case .messageSendSucceeded:
            true
        default:
            false
        }
    }

    private var unreadBoundaryMessageId: Int64? {
        guard model.openedUnreadCount > 0 else { return nil }
        return model.messages.orderedMessageIds.first { messageId in
            guard let message = model.messages.messages[messageId] else { return false }
            return !message.isOutgoing && message.id > model.openedLastReadInboxMessageId
        }
    }

    private var composerText: String {
        model.editingMessage == nil ? model.messageText : model.editMessageText
    }

    private var messages: some View {
        ZStack {
            MacMessageTable(
                model: model,
                chat: chat,
                unreadBoundaryMessageId: unreadBoundaryMessageId,
                shouldFollowLatestMessage: shouldFollowLatestMessage,
                selectedMessageId: $selectedMessageId,
                isAtBottom: $isAtBottom,
                onLoadOlder: loadOlderMessages,
            )
            .onChange(of: chat.chatId) {
                selectedMessageId = nil
                isAtBottom = false
                model.latestHistoryTargetMessageId = nil
            }
            .overlay(alignment: .bottomTrailing) {
                if !isAtBottom,
                   model.messages.orderedMessageIds.last != nil
                {
                    Button {
                        Task { await model.loadLatestMessages() }
                    } label: {
                        if model.isLoadingLatestMessages {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 28, height: 28)
                        } else {
                            Image(systemName: "arrow.down")
                                .frame(width: 28, height: 28)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(Circle())
                    .padding(12)
                    .accessibilityLabel("Scroll to Bottom")
                    .accessibilityHint("Moves to the most recent message")
                    .disabled(model.isLoadingLatestMessages)
                }
            }
            .overlay(alignment: .top) {
                if model.isLoadingOlderMessages {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }
            }
            if model.isLoadingMessages, model.messages.orderedMessageIds.isEmpty {
                ProgressView("Loading messages…")
                    .padding()
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let contextMessage = model.editingMessage ?? model.replyingToMessage {
                HStack(spacing: 8) {
                    Image(systemName: model.editingMessage == nil ? "arrowshape.turn.up.left" : "square.and.pencil")
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.editingMessage == nil ? "Replying to message" : "Editing message")
                            .font(.caption.bold())
                        Text(macMessageText(contextMessage))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Cancel", systemImage: "xmark") {
                        model.cancelReplyOrEdit()
                    }
                    .labelStyle(.iconOnly)
                }
            }

            if !model.selectedPhotoURLs.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.selectedPhotoURLs, id: \.self) { url in
                            ZStack(alignment: .topTrailing) {
                                if let image = NSImage(contentsOf: url) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .accessibilityLabel("Selected photo \(url.lastPathComponent)")
                                }
                                Button("Remove \(url.lastPathComponent)", systemImage: "xmark.circle.fill") {
                                    model.removeSelectedPhoto(url)
                                }
                                .labelStyle(.iconOnly)
                            }
                        }
                    }
                }
                .accessibilityLabel("\(model.selectedPhotoURLs.count) photos selected")
            }

            if !model.selectedDocumentURLs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.selectedDocumentURLs, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc.fill")
                                .accessibilityHidden(true)
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Button("Remove \(url.lastPathComponent)", systemImage: "xmark.circle.fill") {
                                model.removeSelectedDocument(url)
                            }
                            .labelStyle(.iconOnly)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Attached file \(url.lastPathComponent)")
                    }
                }
            }

            if model.isRecordingVoice {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text("Recording \(telegramClockDuration(Int(model.voiceRecordingDuration)))")
                        .monospacedDigit()
                    Spacer()
                    Button("Cancel Recording", systemImage: "xmark", role: .cancel) {
                        model.cancelVoiceRecording()
                    }
                    Button("Send Voice Message", systemImage: "paperplane.fill") {
                        model.sendVoiceRecording()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    Menu("Attach", systemImage: "paperclip") {
                        Button("Photos", systemImage: "photo") { model.choosePhotos() }
                        Button("Files", systemImage: "doc") { model.chooseDocuments() }
                    }
                    .labelStyle(.iconOnly)
                    .help("Attach photos or files")

                    if model.editingMessage == nil {
                        MacComposerTextField(
                            text: $model.messageText,
                            accessibilityLabel: "Message",
                            onPasteFiles: model.attachPastedFiles,
                            onSubmit: model.submitComposer,
                        )
                        .frame(minHeight: 32, idealHeight: 48, maxHeight: 112)
                    } else {
                        MacComposerTextField(
                            text: $model.editMessageText,
                            accessibilityLabel: "Edit message",
                            onPasteFiles: { _ in false },
                            onSubmit: model.submitComposer,
                        )
                        .frame(minHeight: 32, idealHeight: 48, maxHeight: 112)
                    }

                    if model.editingMessage == nil,
                       model.selectedDocumentURLs.isEmpty,
                       model.selectedPhotoURLs.isEmpty,
                       composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    {
                        Button("Record Voice Message", systemImage: "mic.fill") {
                            Task { await model.startVoiceRecording() }
                        }
                        .labelStyle(.iconOnly)
                    } else {
                        Button(
                            model.editingMessage == nil ? "Send" : "Save Changes",
                            systemImage: model.editingMessage == nil ? "paperplane.fill" : "checkmark",
                        ) {
                            model.submitComposer()
                        }
                        .labelStyle(.iconOnly)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(
                            model.selectedDocumentURLs.isEmpty
                                && model.selectedPhotoURLs.isEmpty
                                && composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        )
                    }
                }
            }
        }
        .padding(12)
    }

    private func loadOlderMessages() {
        guard !model.isLoadingOlderMessages else { return }
        Task { _ = await model.loadOlderMessages() }
    }
}
