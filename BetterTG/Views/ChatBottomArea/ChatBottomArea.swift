// ChatBottomArea.swift

import Combine
import PhotosUI
import SwiftUI
import TDLibKit
import UniformTypeIdentifiers

struct ChatBottomArea: View {
    var focused: FocusState<Bool>.Binding

    @Namespace var namespace
    @Environment(ChatVM.self) var chatVM
    @State private var hasBegunRecording = false

    var body: some View {
        @Bindable var chatVM = chatVM
        VStack(spacing: 5) {
            topSide
                .transition(.move(edge: .bottom).combined(with: .opacity))
            
            if !chatVM.displayedImages.isEmpty {
                photosScroll
            }

            if !chatVM.displayedDocuments.isEmpty {
                documentsList
            }

            HStack(alignment: .bottom, spacing: 10) {
                if chatVM.recordingVoiceNote {
                    recordingIndicator
                } else {
                    leftSide

                    textField
                }

                rightSide
            }
        }
        .onDisappear { Task.background { [chatVM] in await chatVM.updateDraft() } }
        .task(id: chatVM.replyMessage) { await chatVM.updateDraft() }
        .task(id: chatVM.editCustomMessage) { chatVM.setEditMessageText(from: chatVM.editCustomMessage?.message) }
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
            Task { await chatVM.stageDocuments(urls) }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(.bar)
        .clipShape(.rect(cornerRadius: 15))
        .padding([.bottom, .horizontal], 5)
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
                .accessibilityElement()
                .accessibilityLabel("Stop Recording")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { chatVM.mediaStopRecordingVoice(
                    duration: Int(chatVM.timerCount),
                    wave: chatVM.wave,
                ) }
                .accessibilityHidden(!chatVM.recordingVoiceNote)
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
        .onChange(of: chatVM.displayedImages) { nc.post(name: .localScrollToLastOnFocus) }
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
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(.white)
                    .font(.system(size: 25))
            }
            .menuOrder(.fixed)
            .frame(height: 36)
            .padding(.bottom, 2)
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
                NavigationControllerWrapper {
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
                nc.post(name: .localScrollToLastOnFocus)
            } else {
                focused.wrappedValue = true
            }
        }
        .onChange(of: chatVM.editCustomMessage) {
            if chatVM.editCustomMessage == nil {
                nc.post(name: .localScrollToLastOnFocus)
            } else {
                focused.wrappedValue = true
            }
        }
        .onChange(of: focused.wrappedValue) {
            nc.post(name: .localScrollToLastOnFocus)
            guard focused.wrappedValue else { return }
            withAnimation { chatVM.showDetail = false }
        }
    }
    
    // Stays mounted for the whole record gesture (touch-down through lock/cancel/send) —
    // swapping it out mid-drag would tear down the DragGesture and lose touch tracking.
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
        .accessibilityElement()
        .accessibilityLabel(
            chatVM.recordingLocked ? "Send Voice Message" :
                chatVM.showSendButton ? "Send Message" : "Record Voice Message"
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if chatVM.recordingLocked {
                chatVM.mediaStopRecordingVoice(duration: Int(chatVM.timerCount), wave: chatVM.wave)
            } else if chatVM.showSendButton {
                chatVM.sendMessageTask?.cancel()
                chatVM.sendMessageTask = Task.main { await chatVM.sendMessage() }
            } else {
                Task.main { await chatVM.mediaStartRecordingVoice() }
            }
        }
        .accessibilityAction(named: "Record Voice Message") {
            Task.main { await chatVM.mediaStartRecordingVoice() }
        }
    }

    private var documentsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(chatVM.displayedDocuments, id: \.self) { url in
                HStack {
                    Image(systemName: "doc.fill")
                        .accessibilityHidden(true)
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    Button("Remove \(url.lastPathComponent)", systemImage: "xmark.circle.fill") {
                        chatVM.displayedDocuments.removeAll { $0 == url }
                        chatVM.setShowSendButton()
                    }
                    .labelStyle(.iconOnly)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Attached file \(url.lastPathComponent)")
            }
        }
        .padding(8)
        .background(Color.gray6)
        .clipShape(.rect(cornerRadius: 10))
    }

    // Thresholds mirror Telegram's own recording button: drag left to cancel,
    // drag up to lock into hands-free recording.
    var voiceRecordingGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !chatVM.recordingLocked else { return }
                if !chatVM.recordingVoiceNote, !hasBegunRecording {
                    hasBegunRecording = true
                    Task.main { await chatVM.mediaStartRecordingVoice() }
                }
                guard chatVM.recordingVoiceNote else { return }
                chatVM.recordingDragTranslation = value.translation
                if value.translation.height < -110 {
                    withAnimation { chatVM.recordingLocked = true }
                } else if value.translation.width < -150 {
                    chatVM.cancelRecordingVoice()
                    hasBegunRecording = false
                }
            }
            .onEnded { value in
                defer { hasBegunRecording = false }
                guard chatVM.recordingVoiceNote, !chatVM.recordingLocked else { return }
                if value.translation.width < -100 || value.predictedEndTranslation.width < -400 {
                    chatVM.cancelRecordingVoice()
                } else if value.translation.height < -60 || value.predictedEndTranslation.height < -400 {
                    withAnimation { chatVM.recordingLocked = true }
                } else {
                    chatVM.mediaStopRecordingVoice(duration: Int(chatVM.timerCount), wave: chatVM.wave)
                }
            }
    }
    
    @ViewBuilder var topSide: some View {
        if let editCustomMessage = chatVM.editCustomMessage {
            replyMessageView(editCustomMessage, type: .edit)
        } else if let replyMessage = chatVM.replyMessage {
            replyMessageView(replyMessage, type: .reply)
        }
    }
    
    var photosScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .center, spacing: 5) {
                ForEach(Array(chatVM.displayedImages.enumerated()), id: \.element.id) { index, photo in
                    photo.image
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: 10))
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Photo \(index + 1) of \(chatVM.displayedImages.count)")
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation {
                                    chatVM.displayedImages.removeAll(where: { photo.id == $0.id })
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .blue)
                                    .padding(5)
                            }
                            .accessibilityLabel("Remove Photo \(index + 1)")
                        }
                }
            }
        }
        .frame(height: 120)
        .clipShape(.rect(cornerRadius: 15))
        .padding(5)
        .background(Color.gray6)
        .clipShape(.rect(cornerRadius: 15))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    @ViewBuilder var textField: some View {
        @Bindable var chatVM = chatVM
        Group {
            if chatVM.editCustomMessage == nil {
                CustomTextField("Message...", text: $chatVM.text)
                    .onReceive(nc.publisher(for: .localPasteImages)) { notification in
                        guard let images = notification.object as? [SelectedImage] else { return }
                        withAnimation { chatVM.displayedImages = images }
                    }
            } else {
                CustomTextField("Edit...", text: $chatVM.editMessageText, focus: true)
            }
        }
        .focused(focused)
        .lineLimit(10)
        .padding(.horizontal, 5)
        .background(Color.gray6)
        .clipShape(.rect(cornerRadius: 15))
//        .onReceive(
//            Just(text)
//                .throttle(
//                    for: 2,
//                    scheduler: DispatchQueue.global(qos: .background),
//                    latest: true
//                )
//        ) { text in
//            Task.background {
//                if !text.characters.isEmpty {
//                    await tdSendChatAction(.chatActionTyping)
//                } else {
//                    await tdSendChatAction(.chatActionCancel)
//                }
//            }
//        }
    }
    
    // Cancel is always tappable (needed for VoiceOver, which never drives the slide gesture);
    // the slide-to-cancel hint is an additional affordance for sighted users while unlocked.
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
}
