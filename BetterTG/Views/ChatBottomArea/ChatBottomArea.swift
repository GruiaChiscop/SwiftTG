// ChatBottomArea.swift

import Combine
import PhotosUI
import SwiftUI
import TDLibKit
import UniformTypeIdentifiers

struct ChatBottomArea: View {
    // MARK: Internal

    var focused: FocusState<Bool>.Binding
    var onAttachmentPreviewDismissed: () -> Void

    @Namespace var namespace
    @Environment(ChatVM.self) var chatVM

    /// Thresholds mirror Telegram's own recording button: drag left to cancel,
    /// drag up to lock into hands-free recording.
    ///
    /// Recording only starts once the press has been held past `minimumDuration` - a plain tap
    /// (release before that) does nothing, rather than starting and instantly stopping a
    /// near-zero-length recording. There's no video-message mode to switch to on a quick tap
    /// (round-video recording isn't implemented), so a tap is simply a no-op for now.
    var voiceRecordingGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag) = value, !chatVM.recordingLocked else { return }
                if !chatVM.recordingVoiceNote, !hasBegunRecording {
                    hasBegunRecording = true
                    Task.main { await chatVM.mediaStartRecordingVoice() }
                }
                guard chatVM.recordingVoiceNote, let drag else { return }
                chatVM.recordingDragTranslation = drag.translation
                if drag.translation.height < -110 {
                    withAnimation { chatVM.recordingLocked = true }
                } else if drag.translation.width < -150 {
                    discardRecordingFromGesture()
                    hasBegunRecording = false
                }
            }
            .onEnded { value in
                defer { hasBegunRecording = false }
                guard case .second(true, let drag) = value,
                      chatVM.recordingVoiceNote, !chatVM.recordingLocked
                else { return }
                let translation = drag?.translation ?? .zero
                let predictedTranslation = drag?.predictedEndTranslation ?? .zero
                if translation.width < -100 || predictedTranslation.width < -400 {
                    discardRecordingFromGesture()
                } else if translation.height < -60 || predictedTranslation.height < -400 {
                    withAnimation { chatVM.recordingLocked = true }
                } else {
                    chatVM.mediaStopRecordingVoice(duration: Int(chatVM.timerCount), wave: chatVM.wave)
                }
            }
    }
    
    /// Gated on the picker/camera/file-importer sheets also being closed - each of those stages
    /// attachments asynchronously (image loading, security-scoped copy) while still technically
    /// presented, so presenting this sheet purely off "attachments non-empty" could momentarily
    /// race with one of them still being on screen.
    var showAttachmentPreview: Bool {
        (!chatVM.displayedImages.isEmpty || !chatVM.displayedDocuments.isEmpty)
            && !chatVM.showPhotoPickerView
            && !chatVM.showCameraView
            && !chatVM.showDocumentPicker
    }

    var showsTopSide: Bool {
        if chatVM.editCustomMessage != nil || chatVM.replyMessage != nil {
            return true
        }
        return chatVM.displayedImages.isEmpty
            && chatVM.displayedDocuments.isEmpty
            && chatVM.activeLinkPreviewComposer.preview != nil
    }

    var body: some View {
        @Bindable var chatVM = chatVM
        VStack(spacing: 0) {
            if showsTopSide {
                topSide
                    .padding(.bottom, 5)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 6) {
                if chatVM.recordingVoiceNote {
                    recordingIndicator
                } else {
                    leftSide

                    textField

                    Button {
                        showsStickerPicker = true
                    } label: {
                        Label("Stickers", systemImage: "face.smiling")
                            .labelStyle(.iconOnly)
                    }
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .disabled(chatVM.editCustomMessage != nil)
                }

                rightSide
            }
        }
        .disabled(chatVM.isSubmittingMessage)
        .onDisappear { Task.background { [chatVM] in await chatVM.updateDraft() } }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase != .active else { return }
            Task.background { [chatVM] in await chatVM.updateDraft() }
        }
        .alert("Error", isPresented: $chatVM.errorShown) {
            Text("""
            Access to Microphone isn't granted.
            Go to Settings -> BetterTG -> Microphone
            if you want to record Voice
            """)
        }
        .fileImporter(
            isPresented: $chatVM.showDocumentPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
        ) { result in
            guard case .success(let urls) = result else { return }
            Task { @MainActor in await chatVM.stageDocuments(urls) }
        }
        .sheet(
            isPresented: Binding(
                get: { showAttachmentPreview },
                set: { isPresented in
                    guard !isPresented else { return }
                    withAnimation {
                        chatVM.displayedImages.removeAll()
                        chatVM.displayedDocuments.removeAll()
                    }
                },
            ),
            onDismiss: onAttachmentPreviewDismissed,
        ) {
            AttachmentPreviewView()
        }
        .sheet(isPresented: $showsPollComposer) {
            TelegramPollComposerView { draft in
                try await TelegramPollSending.send(
                    draft: draft,
                    service: chatVM.service,
                    chatId: chatVM.customChat.chat.id,
                    replyToMessageId: chatVM.replyMessage?.id,
                )
                chatVM.replyMessage = nil
                await chatVM.updateDraft()
            }
        }
        .sheet(isPresented: $showsStickerPicker) {
            TelegramStickerPickerView(
                service: chatVM.service,
                chatId: chatVM.customChat.chat.id,
                replyToMessageId: chatVM.replyMessage?.id,
                onSent: {
                    chatVM.replyMessage = nil
                    await chatVM.updateDraft()
                },
            ) { sticker in
                TelegramStickerView(
                    sticker: sticker,
                    service: chatVM.service,
                    maxSide: 76,
                    playsAnimation: false,
                )
            }
        }
        .padding(.horizontal, 8)
        .background(.bar)
        .clipShape(.rect(cornerRadius: 15))
        .padding(.horizontal, 5)
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(.blue)
                .frame(width: 96, height: 96)
                .overlay(alignment: .center) {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.white)
                        .font(.title2)
                }
                .disabled(!chatVM.recordingVoiceNote)
                .opacity(chatVM.recordingLocked ? 1 : 0)
                .scaleEffect(chatVM.recordingLocked ? 1 : 0)
                .offset(x: 20, y: 20)
                .onTapGesture { chatVM.mediaStopRecordingVoice(duration: Int(chatVM.timerCount), wave: chatVM.wave) }
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            if chatVM.recordingVoiceNote, !chatVM.recordingLocked {
                VStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                    Image(systemName: "chevron.up")
                }
                .font(.caption)
                .foregroundStyle(.white)
                .padding(10)
                .background(Color.gray6)
                .clipShape(.rect(cornerRadius: 18))
                .offset(x: -20, y: max(-70, chatVM.recordingDragTranslation.height) - 10)
                .opacity(1 - min(1, abs(chatVM.recordingDragTranslation.height) / 110))
                .accessibilityHidden(true)
                .transition(.opacity)
            }
        }
        .onChange(of: chatVM.recordingVoiceNote) { _, isRecording in
            if isRecording {
                chatVM.startTimer()
            } else {
                chatVM.stopTimer()
            }
        }
        .onChange(of: chatVM.recordingLocked) { _, isLocked in
            guard isLocked else { return }
            UIAccessibility.post(notification: .announcement, argument: "Recording locked")
        }
        .onChange(of: chatVM.displayedImages) { nc.post(name: .localScrollToLastIfNeeded) }
        .task(id: chatVM.customChat.chat.id) {
            pollIsAvailable = false
            pollIsAvailable = await TelegramPollSending.isAvailable(
                service: chatVM.service,
                chatId: chatVM.customChat.chat.id,
            )
        }
        .onReceive(nc.publisher(for: .localOnSelectedImagesDrop)) { notification in
            guard let selectedImages = notification.object as? [SelectedImage] else { return }
            withAnimation {
                chatVM.displayedDocuments.removeAll()
                chatVM.displayedImages = selectedImages
            }
        }
    }
    
    @ViewBuilder var leftSide: some View {
        @Bindable var chatVM = chatVM
        HStack(spacing: 10) {
            Menu {
                Button {
                    withAnimation {
                        chatVM.displayedImages.removeAll()
                        chatVM.displayedDocuments.removeAll()
                    }
                    chatVM.showPhotoPickerView = true
                } label: {
                    Label("Attach Photos", systemImage: "photo")
                }
                Button {
                    chatVM.displayedDocuments.removeAll()
                    chatVM.showCameraView = true
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                }
                Button {
                    chatVM.displayedImages.removeAll()
                    chatVM.showDocumentPicker = true
                } label: {
                    Label("Attach Files", systemImage: "folder")
                }
                if pollIsAvailable {
                    Button {
                        withAnimation {
                            chatVM.displayedImages.removeAll()
                            chatVM.displayedDocuments.removeAll()
                        }
                        showsPollComposer = true
                    } label: {
                        Label("Poll", systemImage: "chart.bar")
                    }
                }
            } label: {
                Label("Attach", systemImage: "paperclip")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white)
                    .font(.system(size: 25))
            }
            .menuOrder(.fixed)
            .disabled(chatVM.editCustomMessage != nil)
            .frame(width: 40, height: 40)
            .sheet(isPresented: $chatVM.showPhotoPickerView) {
                PhotoPicker { index, image, error in
                    if let image {
                        Task.main {
                            withAnimation {
                                chatVM.displayedImages.place(image, at: index)
                            }
                        }
                    } else if let error {
                        print("Error picking image: \(error.localizedDescription)")
                    }
                } clear: {
                    withAnimation {
                        chatVM.displayedImages.removeAll()
                    }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $chatVM.showCameraView) {
                NavigationStack {
                    CameraView { selectedImage in
                        withAnimation { chatVM.displayedImages = [selectedImage] }
                    }
                    .navigationTitle("Camera")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .font(.system(size: 22))
        .foregroundStyle(.white)
        .onChange(of: chatVM.text) { withAnimation { chatVM.showDetail = false } }
        .onChange(of: chatVM.editMessageText) { withAnimation { chatVM.showDetail = false } }
        .onChange(of: chatVM.replyMessage) {
            if chatVM.replyMessage == nil {
                nc.post(name: .localScrollToLastIfNeeded)
            } else {
                focused.wrappedValue = true
            }
        }
        .onChange(of: chatVM.editCustomMessage) {
            if chatVM.editCustomMessage == nil {
                nc.post(name: .localScrollToLastIfNeeded)
            } else {
                focused.wrappedValue = true
            }
        }
        .onChange(of: focused.wrappedValue) {
            guard focused.wrappedValue else { return }
            withAnimation { chatVM.showDetail = false }
        }
    }
    
    /// Stays mounted for the whole record gesture (touch-down through lock/cancel/send) —
    /// swapping it out mid-drag would tear down the DragGesture and lose touch tracking.
    var rightSide: some View {
        Group {
            if chatVM.showSendButton || chatVM.recordingLocked {
                Image("send")
                    .resizable()
                    .clipShape(.circle)
                    .frame(width: 32, height: 32)
                    .padding(.bottom, 3)
            } else {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.white)
                    .padding(.bottom, 5)
            }
        }
        .font(.title2)
        .frame(width: 40, height: 40)
        .contentShape(.rect)
        .transition(.scale)
        .modify {
            if chatVM.recordingLocked {
                $0.onTapGesture { chatVM.mediaStopRecordingVoice(duration: Int(chatVM.timerCount), wave: chatVM.wave) }
            } else if chatVM.showSendButton {
                $0.onTapGesture {
                    chatVM.sendMessageTask?.cancel()
                    chatVM.sendMessageTask = Task.main { await chatVM.sendMessage() }
                }
            } else {
                $0.gesture(voiceRecordingGesture)
            }
        }
        .onChange(of: chatVM.editMessageText, chatVM.setShowSendButton)
        .onChange(of: chatVM.text, chatVM.setShowSendButton)
        .onChange(of: chatVM.displayedImages, chatVM.setShowSendButton)
        .onChange(of: chatVM.displayedDocuments, chatVM.setShowSendButton)
        .onChange(of: chatVM.editCustomMessage, chatVM.setShowSendButton)
        .disabled(chatVM.isSubmittingMessage)
        .accessibilityElement()
        .accessibilityLabel(
            chatVM.recordingLocked
                ? "Send Voice Message"
                : chatVM.showSendButton ? "Send Message" : "Record Voice Message",
        )
        .accessibilityAddTraits(.isButton)
        // While recording but not yet locked, this still visually shows the mic glyph as a
        // placeholder, but offering "Record Voice Message" here would be redundant/confusing
        // alongside the recording indicator's Cancel action and the lock circle's Send action.
        .accessibilityHidden(chatVM.recordingVoiceNote && !chatVM.recordingLocked)
        .modify {
            if !chatVM.recordingLocked, !chatVM.showSendButton {
                $0.accessibilityHint("Double-tap and hold to record a voice message")
            } else {
                $0
            }
        }
        .accessibilityAction {
            if chatVM.recordingLocked {
                chatVM.mediaStopRecordingVoice(duration: Int(chatVM.timerCount), wave: chatVM.wave)
            } else if chatVM.showSendButton {
                chatVM.sendMessageTask?.cancel()
                chatVM.sendMessageTask = Task.main { await chatVM.sendMessage() }
            }
            // Recording itself must only start from a genuine hold, matching the sighted-user
            // contract exactly (see voiceRecordingGesture) - a plain double-tap here is a no-op,
            // same as a plain tap for sighted users; VoiceOver's "double-tap and hold" reaches
            // voiceRecordingGesture directly instead of this shortcut.
        }
    }

    var topSide: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let editCustomMessage = chatVM.editCustomMessage {
                replyMessageView(editCustomMessage, type: .edit)
            } else if let replyMessage = chatVM.replyMessage {
                replyMessageView(replyMessage, type: .reply)
            }

            if chatVM.displayedImages.isEmpty,
               chatVM.displayedDocuments.isEmpty,
               let preview = chatVM.activeLinkPreviewComposer.preview
            {
                linkPreviewAccessory(preview)
            }
        }
    }

    var textField: some View {
        @Bindable var chatVM = chatVM
        let isEditing = chatVM.editCustomMessage != nil
        return MessageTextEditor(
            isEditing ? "Edit a message" : "Type a message",
            text: isEditing ? $chatVM.editMessageText : $chatVM.text,
            contextID: chatVM.editCustomMessage.map { AnyHashable($0.id) } ?? AnyHashable("composer"),
            onSubmit: submitMessage,
            onPasteImages: isEditing
                ? nil
                : { images in
                    withAnimation {
                        chatVM.displayedDocuments.removeAll()
                        chatVM.displayedImages.append(contentsOf: images)
                    }
                },
        )
        .focused(focused)
        .disabled(chatVM.isSubmittingMessage)
        .lineLimit(10)
        .padding(.horizontal, 5)
        .background(Color.gray6)
        .clipShape(.rect(cornerRadius: 15))
    }
    
    /// Cancel is always tappable (needed for VoiceOver, which never drives the slide gesture);
    /// the slide-to-cancel hint is an additional affordance for sighted users while unlocked.
    var recordingIndicator: some View {
        HStack(spacing: 8) {
            Button {
                chatVM.cancelRecordingVoice()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Cancel Recording")

            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text(chatVM.formattedTimerCount)
                .foregroundStyle(.white)
                .monospacedDigit()

            Spacer()

            if !chatVM.recordingLocked {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Slide to Cancel")
                }
                .font(.subheadline)
                .foregroundStyle(.gray)
                .offset(x: min(0, chatVM.recordingDragTranslation.width / 3))
                .opacity(1 - min(1, abs(chatVM.recordingDragTranslation.width) / 150))
                .accessibilityHidden(true)
            }
        }
        .padding(.bottom, 6)
    }

    func linkPreviewAccessory(_ preview: LinkPreview) -> some View {
        HStack(alignment: .top, spacing: 6) {
            TelegramLinkPreviewView(preview: preview, service: chatVM.service)
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu("Link Preview Options", systemImage: "ellipsis.circle") {
                Button(chatVM.activeLinkPreviewComposer.showsAboveText ? "Move Below Text" : "Move Above Text") {
                    chatVM.activeLinkPreviewComposer.togglePosition()
                }
                if preview.hasLargeMedia {
                    Button(chatVM.activeLinkPreviewComposer.showsLargeMedia ? "Use Small Media" : "Use Large Media") {
                        chatVM.activeLinkPreviewComposer.toggleMediaSize()
                    }
                }
            }
            .labelStyle(.iconOnly)

            Button("Remove Link Preview", systemImage: "xmark") {
                chatVM.activeLinkPreviewComposer.dismiss()
            }
            .labelStyle(.iconOnly)
        }
    }

    func replyMessageView(_ customMessage: CustomMessage, type: ReplyMessageType) -> some View {
        HStack {
            ReplyMessageView(customMessage: customMessage, type: type, onTap: {
                var id: Int64?
                switch type {
                case .reply: id = chatVM.replyMessage?.id
                case .edit: id = chatVM.editCustomMessage?.id
                default: break
                }
                guard let id else { return }
                chatVM.scrollTo(id: id)
            })
            .background(Color.gray6)
            .clipShape(.rect(cornerRadius: 15))

            Button {
                withAnimation {
                    chatVM.replyMessage = nil
                    chatVM.editCustomMessage = nil
                }
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(type == .edit ? "Cancel Edit" : "Cancel Reply")
        }
    }

    // MARK: Private

    @Environment(\.scenePhase) private var scenePhase

    @State private var showsPollComposer = false
    @State private var showsStickerPicker = false
    @State private var pollIsAvailable = false

    @State private var hasBegunRecording = false

    private func discardRecordingFromGesture() {
        chatVM.cancelRecordingVoice()
        UIAccessibility.post(notification: .announcement, argument: "Recording discarded")
    }

    private func submitMessage() {
        chatVM.sendMessageTask?.cancel()
        chatVM.sendMessageTask = Task.main { await chatVM.sendMessage() }
    }
}
