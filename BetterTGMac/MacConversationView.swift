// MacConversationView.swift

import AppKit
import SwiftUI
import TDLibKit

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
            if model.isConversationSearchActive {
                conversationSearchField
                Divider()
            } else if model.currentPinnedMessage != nil {
                pinnedMessageBanner
                Divider()
            }
            messages
            Divider()
            if model.isConversationSearchActive {
                conversationSearchNavigationBar
            } else if chat.kind != .channel || chat.canPostMessages == true {
                composer
            } else {
                Text("Only channel administrators can post.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .sheet(isPresented: $showsChatInfo) {
            MacChatInfoView(model: model, chat: chat)
        }
        .sheet(isPresented: $showsPinnedMessages) {
            MacPinnedMessagesView(model: model)
        }
        .sheet(isPresented: $showsScheduleSendPicker) {
            MacScheduleSendView(allowsSendWhenOnline: model.openedChat?.kind == .privateChat) { schedulingState in
                model.submitComposer(schedulingState: schedulingState)
            }
        }
        .sheet(isPresented: $showsScheduleVoicePicker) {
            MacScheduleSendView(allowsSendWhenOnline: model.openedChat?.kind == .privateChat) { schedulingState in
                model.sendVoiceRecording(schedulingState: schedulingState)
            }
        }
        .sheet(isPresented: $showsPollComposer) {
            TelegramPollComposerView { draft in
                guard let chatId = model.openedChatId else { return }
                try await TelegramPollSending.send(
                    draft: draft,
                    service: model.service,
                    chatId: chatId,
                    replyToMessageId: model.replyingToMessage?.id,
                )
                model.replyingToMessage = nil
                model.saveCurrentDraft()
            }
        }
        .sheet(isPresented: $showsStickerPicker) {
            TelegramStickerPickerView(
                service: model.service,
                chatId: chat.chatId,
                replyToMessageId: model.replyingToMessage?.id,
                onSent: {
                    model.replyingToMessage = nil
                    model.saveCurrentDraft()
                },
            ) { sticker in
                MacStickerView(
                    model: model,
                    sticker: sticker,
                    maxSide: 76,
                    playsAnimation: false,
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { !model.selectedPhotoURLs.isEmpty || !model.selectedDocumentURLs.isEmpty },
            set: { isPresented in
                guard !isPresented else { return }
                model.selectedPhotoURLs.removeAll()
                model.selectedDocumentURLs.removeAll()
            },
        )) {
            MacAttachmentPreview(model: model)
        }
        .onChange(of: model.isConversationSearchActive) { _, isActive in
            conversationSearchFocused = isActive
        }
        .onChange(of: model.conversationSearchQuery) {
            model.conversationSearchQueryDidChange()
        }
        .task(id: chat.chatId) {
            pollIsAvailable = false
            pollIsAvailable = await TelegramPollSending.isAvailable(
                service: model.service,
                chatId: chat.chatId,
            )
        }
    }

    // MARK: Private

    @FocusState private var conversationSearchFocused
    @State private var isAtBottom = false
    @State private var showsChatInfo = false
    @State private var showsPinnedMessages = false
    @State private var showsPollComposer = false
    @State private var showsScheduleSendPicker = false
    @State private var showsScheduleVoicePicker = false
    @State private var showsStickerPicker = false
    @State private var pollIsAvailable = false

    private var shouldFollowLatestMessage: Bool {
        switch model.messages.change {
        case .newMessage(let update):
            isAtBottom || update.message.isOutgoing
        case .messageSendSucceeded:
            true
        case .messageSendFailed:
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
        (model.editingMessage == nil ? model.messageText : model.editMessageText).string
    }

    private var pinnedMessageSummary: String {
        guard let message = model.currentPinnedMessage else { return "" }
        return telegramQuotedMessageExcerpt(telegramMessageContentDescription(message))
    }

    private var conversationSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Search messages", text: $model.conversationSearchQuery)
                .textFieldStyle(.roundedBorder)
                .focused($conversationSearchFocused)
                .onSubmit {
                    if model.canSelectOlderConversationSearchResult {
                        model.selectOlderConversationSearchResult()
                    }
                }

            Button("Cancel", role: .cancel) {
                model.endConversationSearch()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(10)
        .background(.bar)
    }

    private var pinnedMessageBanner: some View {
        HStack(spacing: 8) {
            Button {
                guard let message = model.currentPinnedMessage else { return }
                model.activateChat(chat.chatId, messageId: message.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pinned Message")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text(pinnedMessageSummary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button("Show All Pinned Messages", systemImage: "chevron.right") {
                showsPinnedMessages = true
            }
            .labelStyle(.iconOnly)
            .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var conversationSearchNavigationBar: some View {
        HStack(spacing: 12) {
            if model.isSearchingConversation {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }

            Text(model.conversationSearchStatus)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Search results, \(model.conversationSearchStatus)")

            Spacer()

            Button("Older result", systemImage: "chevron.up") {
                model.selectOlderConversationSearchResult()
            }
            .labelStyle(.iconOnly)
            .disabled(!model.canSelectOlderConversationSearchResult || model.isSearchingConversation)

            Button("Newer result", systemImage: "chevron.down") {
                model.selectNewerConversationSearchResult()
            }
            .labelStyle(.iconOnly)
            .disabled(!model.canSelectNewerConversationSearchResult || model.isSearchingConversation)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        .background(.bar)
    }

    private var messages: some View {
        ZStack {
            MacMessageTable(
                model: model,
                chat: chat,
                unreadBoundaryMessageId: unreadBoundaryMessageId,
                shouldFollowLatestMessage: shouldFollowLatestMessage,
                isAtBottom: $isAtBottom,
            )
            .onChange(of: chat.chatId) {
                isAtBottom = false
                model.latestHistoryTargetMessageId = nil
            }
            .overlay(alignment: .bottomTrailing) {
                if !isAtBottom,
                   model.messages.orderedMessageIds.last != nil
                {
                    Button("Scroll to Bottom", systemImage: "arrow.down") {
                        Task { await model.loadLatestMessages() }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(12)
                }
            }
            .overlay(alignment: .top) {
                if model.isLoadingOlderMessages {
                    ProgressView("Loading...")
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

            if model.selectedPhotoURLs.isEmpty,
               model.selectedDocumentURLs.isEmpty,
               let preview = model.activeLinkPreviewComposer.preview
            {
                linkPreviewAccessory(preview)
            }

            if model.isRecordingVoice {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text(telegramClockDuration(Int(model.voiceRecordingDuration)))
                        .monospacedDigit()
                    Spacer()
                    Button("Cancel Recording", systemImage: "xmark", role: .cancel) {
                        model.cancelVoiceRecording()
                    }
                    Button("Send Voice Message", systemImage: "paperplane.fill") {
                        model.sendVoiceRecording()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .contextMenu {
                        Button("Send Later…", systemImage: "clock") {
                            showsScheduleVoicePicker = true
                        }
                    }
                }
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    Menu("Attach", systemImage: "paperclip") {
                        Button("Photos", systemImage: "photo") { model.choosePhotos() }
                        Button("Files", systemImage: "doc") { model.chooseDocuments() }
                        if pollIsAvailable {
                            Button("Poll", systemImage: "chart.bar") { showsPollComposer = true }
                                .disabled(model.editingMessage != nil)
                        }
                    }
                    .labelStyle(.iconOnly)
                    .help("Attach photos or files")

                    let isEditing = model.editingMessage != nil
                    MacComposerTextField(
                        text: isEditing ? $model.editMessageText : $model.messageText,
                        accessibilityLabel: isEditing ? "Edit message" : "Message",
                        contextID: model.editingMessage.map { AnyHashable($0.id) } ?? AnyHashable("composer"),
                        onPasteFiles: isEditing ? { _ in false } : model.attachPastedFiles,
                        onSubmit: { model.submitComposer() },
                    )
                    .frame(minHeight: 32, idealHeight: 48, maxHeight: 112)

                    Button("Stickers", systemImage: "face.smiling") {
                        showsStickerPicker = true
                    }
                    .labelStyle(.iconOnly)
                    .disabled(model.editingMessage != nil)

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
                        .contextMenu {
                            if model.editingMessage == nil {
                                Button("Send Later…", systemImage: "clock") {
                                    showsScheduleSendPicker = true
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .disabled(model.isSubmittingMessage)
    }

    private func linkPreviewAccessory(_ preview: LinkPreview) -> some View {
        HStack(alignment: .top, spacing: 6) {
            MacLinkPreviewView(model: model, preview: preview)
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu("Link Preview Options", systemImage: "ellipsis.circle") {
                Button(model.activeLinkPreviewComposer.showsAboveText ? "Move Below Text" : "Move Above Text") {
                    model.activeLinkPreviewComposer.togglePosition()
                }
                if preview.hasLargeMedia {
                    Button(model.activeLinkPreviewComposer.showsLargeMedia ? "Use Small Media" : "Use Large Media") {
                        model.activeLinkPreviewComposer.toggleMediaSize()
                    }
                }
            }
            .labelStyle(.iconOnly)

            Button("Remove Link Preview", systemImage: "xmark") {
                model.activeLinkPreviewComposer.dismiss()
            }
            .labelStyle(.iconOnly)
        }
    }
}
