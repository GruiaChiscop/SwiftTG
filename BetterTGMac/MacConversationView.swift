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
            messages
            Divider()
            composer
        }
        .navigationTitle(chat.title)
    }

    // MARK: Private

    @AccessibilityFocusState private var voiceOverFocusedMessageId: Int64?
    @FocusState private var messageListHasKeyboardFocus: Bool
    @State private var selectedMessageId: Int64?
    @State private var historyAnchorMessageId: Int64?
    @State private var hasPositionedInitialMessages = false
    @State private var isAtBottom = false

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
        ScrollViewReader { proxy in
            List {
                if model.isLoadingMessages {
                    ProgressView("Loading messages…")
                        .padding()
                }
                ForEach(Array(model.messages.orderedMessageIds.enumerated()), id: \.element) { index, messageId in
                    if let message = model.messages.messages[messageId] {
                        if startsNewDay(at: index) {
                            MacMessageDayHeader(title: telegramMessageDayHeading(message.date))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        if unreadBoundaryMessageId == messageId {
                            MacUnreadMessagesHeader(count: model.openedUnreadCount)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        MacMessageRow(
                            model: model,
                            message: message,
                            lastReadOutboxMessageId: chat.lastReadOutboxMessageId,
                        )
                        .id(messageId)
                        .accessibilityFocused($voiceOverFocusedMessageId, equals: messageId)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .onAppear {
                            guard messageId == model.messages.orderedMessageIds.first,
                                  hasPositionedInitialMessages,
                                  !model.isLoadingMessages
                            else { return }
                            loadOlderMessages()
                        }
                        .onScrollVisibilityChange(threshold: 0.2) { isVisible in
                            guard messageId == model.messages.orderedMessageIds.last else { return }
                            isAtBottom = isVisible
                        }
                    }
                }
            }
            .listStyle(.plain)
            .focused($messageListHasKeyboardFocus)
            .onMoveCommand { direction in
                moveMessageFocus(direction, using: proxy)
            }
            .onChange(of: voiceOverFocusedMessageId) { _, messageId in
                guard let messageId else { return }
                selectedMessageId = messageId
                messageListHasKeyboardFocus = true
            }
            .onChange(of: model.messages.version) {
                if let latestMessageId = model.latestHistoryTargetMessageId,
                   model.messages.messages[latestMessageId] != nil
                {
                    positionAtLatestHistory(
                        model.messages.orderedMessageIds.last ?? latestMessageId,
                        using: proxy,
                    )
                } else if let targetMessageId = model.navigationTargetMessageId,
                          model.messages.messages[targetMessageId] != nil
                {
                    positionSearchResult(targetMessageId, using: proxy)
                } else if let anchorMessageId = historyAnchorMessageId {
                    if model.messages.orderedMessageIds.first != anchorMessageId {
                        proxy.scrollTo(anchorMessageId, anchor: .top)
                        historyAnchorMessageId = nil
                    }
                } else if !hasPositionedInitialMessages,
                          let lastId = model.messages.orderedMessageIds.last
                {
                    positionAtBottom(lastId, using: proxy)
                } else if shouldFollowLatestMessage,
                          let lastId = model.messages.orderedMessageIds.last
                {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
            .onChange(of: model.isLoadingMessages) { _, isLoading in
                guard !isLoading,
                      model.navigationTargetMessageId == nil,
                      let lastId = model.messages.orderedMessageIds.last
                else { return }
                positionAtBottom(lastId, using: proxy)
            }
            .onChange(of: model.navigationTargetMessageId) { _, messageId in
                guard let messageId, model.messages.messages[messageId] != nil else { return }
                positionSearchResult(messageId, using: proxy)
            }
            .onChange(of: chat.chatId) {
                selectedMessageId = nil
                voiceOverFocusedMessageId = nil
                historyAnchorMessageId = nil
                hasPositionedInitialMessages = false
                isAtBottom = false
                model.latestHistoryTargetMessageId = nil
            }
            .overlay(alignment: .bottomTrailing) {
                if hasPositionedInitialMessages,
                   !isAtBottom,
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
                    .keyboardShortcut(.downArrow, modifiers: .command)
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
                        TextField("Message", text: $model.messageText, axis: .vertical)
                            .lineLimit(1...6)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { model.submitComposer() }
                    } else {
                        TextField("Edit message", text: $model.editMessageText, axis: .vertical)
                            .lineLimit(1...6)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { model.submitComposer() }
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

    private func startsNewDay(at index: Int) -> Bool {
        let ids = model.messages.orderedMessageIds
        guard ids.indices.contains(index), let message = model.messages.messages[ids[index]] else { return false }
        guard index > ids.startIndex, let previous = model.messages.messages[ids[index - 1]] else { return true }
        let date = Date(timeIntervalSince1970: TimeInterval(message.date))
        let previousDate = Date(timeIntervalSince1970: TimeInterval(previous.date))
        return !Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: previousDate)
    }

    private func positionSearchResult(_ messageId: Int64, using proxy: ScrollViewProxy) {
        proxy.scrollTo(messageId, anchor: .center)
        selectedMessageId = messageId
        voiceOverFocusedMessageId = messageId
        messageListHasKeyboardFocus = true
        model.navigationTargetMessageId = nil
        hasPositionedInitialMessages = true
    }

    private func moveMessageFocus(_ direction: MoveCommandDirection, using proxy: ScrollViewProxy) {
        let messageIds = model.messages.orderedMessageIds
        guard !messageIds.isEmpty else { return }

        let currentIndex = selectedMessageId.flatMap { messageIds.firstIndex(of: $0) }
        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = max(0, (currentIndex ?? messageIds.endIndex) - 1)
        case .down:
            targetIndex = min(
                messageIds.index(before: messageIds.endIndex),
                (currentIndex ?? messageIds.index(before: messageIds.endIndex)) + 1,
            )
        default:
            return
        }

        let targetMessageId = messageIds[targetIndex]
        selectedMessageId = targetMessageId
        voiceOverFocusedMessageId = targetMessageId
        proxy.scrollTo(targetMessageId)
    }

    private func positionAtBottom(_ messageId: Int64, using proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                proxy.scrollTo(messageId, anchor: .bottom)
            }
            hasPositionedInitialMessages = true
            isAtBottom = true
        }
    }

    private func positionAtLatestHistory(_ messageId: Int64, using proxy: ScrollViewProxy) {
        withAnimation {
            proxy.scrollTo(messageId, anchor: .bottom)
        }
        selectedMessageId = messageId
        voiceOverFocusedMessageId = messageId
        messageListHasKeyboardFocus = true
        isAtBottom = true
        model.latestHistoryTargetMessageId = nil
    }

    private func loadOlderMessages() {
        guard historyAnchorMessageId == nil,
              let anchorMessageId = model.messages.orderedMessageIds.first
        else { return }

        historyAnchorMessageId = anchorMessageId
        Task {
            if await !(model.loadOlderMessages()) {
                historyAnchorMessageId = nil
            }
        }
    }
}

// MARK: - MacMessageDayHeader

private struct MacMessageDayHeader: View {
    let title: String

    var body: some View {
        HStack {
            Spacer()
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - MacUnreadMessagesHeader

private struct MacUnreadMessagesHeader: View {
    // MARK: Internal

    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Divider()
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Divider()
        }
        .frame(height: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Private

    private var title: String {
        "\(count) unread \(count == 1 ? "message" : "messages")"
    }
}
