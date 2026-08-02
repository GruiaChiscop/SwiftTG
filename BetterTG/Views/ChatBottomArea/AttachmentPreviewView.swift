// AttachmentPreviewView.swift

import SwiftUI

/// Full-screen review step shown after picking photos or files, matching Telegram/Unigram's own
/// "send media" screen: a paged preview of what's about to be sent, with one shared caption field
/// and a way to drop individual items before confirming - rather than sending straight from the
/// picker with the caption typed into the regular chat compose field.
struct AttachmentPreviewView: View {
    // MARK: Internal

    @Environment(ChatVM.self) var chatVM

    var body: some View {
        @Bindable var chatVM = chatVM
        NavigationStack {
            Group {
                if !chatVM.displayedImages.isEmpty {
                    TabView(selection: $selectedIndex) {
                        ForEach(Array(chatVM.displayedImages.enumerated()), id: \.element.id) { index, selected in
                            selected.image
                                .resizable()
                                .scaledToFit()
                                .tag(index)
                                .accessibilityLabel("Photo \(index + 1) of \(chatVM.displayedImages.count)")
                        }
                    }
                } else {
                    TabView(selection: $selectedIndex) {
                        ForEach(Array(chatVM.displayedDocuments.enumerated()), id: \.offset) { index, url in
                            documentPreview(for: url)
                                .tag(index)
                        }
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: itemCount > 1 ? .always : .never))
            .background(.black)
            .safeAreaInset(edge: .bottom) {
                captionBar
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                if itemCount > 1 {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Remove", systemImage: "trash", role: .destructive, action: removeSelectedItem)
                    }
                }
            }
            .navigationTitle(itemCount > 1
                ? "\(itemCount) Items"
                : (chatVM.displayedImages.isEmpty ? "Document" : "Photo"))
                .navigationBarTitleDisplayMode(.inline)
        }
        .alert(
            "Send Failed",
            isPresented: Binding(
                get: { chatVM.messageActionError != nil },
                set: {
                    if !$0 {
                        chatVM.messageActionError = nil
                    }
                },
            ),
        ) {
            Button("OK") { chatVM.messageActionError = nil }
        } message: {
            Text(chatVM.messageActionError ?? "Telegram couldn't send the message.")
        }
    }

    // MARK: Private

    @State private var selectedIndex = 0

    private var itemCount: Int {
        chatVM.displayedImages.count + chatVM.displayedDocuments.count
    }

    private var captionBar: some View {
        @Bindable var chatVM = chatVM
        return HStack(alignment: .bottom, spacing: 10) {
            MessageTextEditor("Add a caption...", text: $chatVM.text, onSubmit: send) { images in
                withAnimation {
                    chatVM.displayedDocuments.removeAll()
                    chatVM.displayedImages.append(contentsOf: images)
                }
            }
            .lineLimit(6)
            .padding(.horizontal, 5)
            .background(Color.gray6)
            .clipShape(.rect(cornerRadius: 15))

            Button(action: send) {
                Image("send")
                    .resizable()
                    .clipShape(.circle)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Send")
        }
        .padding(10)
        .background(.bar)
        .disabled(chatVM.isSubmittingMessage)
    }

    private func documentPreview(for url: URL) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.fill")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent)
                .font(.headline)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private func send() {
        chatVM.sendMessageTask?.cancel()
        chatVM.sendMessageTask = Task.main { await chatVM.sendMessage() }
    }

    private func cancel() {
        withAnimation {
            chatVM.displayedImages.removeAll()
            chatVM.displayedDocuments.removeAll()
        }
    }

    private func removeSelectedItem() {
        withAnimation {
            if !chatVM.displayedImages.isEmpty {
                guard chatVM.displayedImages.indices.contains(selectedIndex) else { return }
                chatVM.displayedImages.remove(at: selectedIndex)
            } else {
                guard chatVM.displayedDocuments.indices.contains(selectedIndex) else { return }
                chatVM.displayedDocuments.remove(at: selectedIndex)
            }
            selectedIndex = max(0, selectedIndex - 1)
        }
    }
}
