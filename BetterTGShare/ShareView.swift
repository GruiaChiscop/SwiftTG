// ShareView.swift

import ImageIO
import SwiftUI

// MARK: - ShareAttachmentPreview

/// A file already staged to disk by `ShareViewController.stageFile` - just enough to show the user
/// what's about to be sent, before they've committed to a chat.
struct ShareAttachmentPreview: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let isImage: Bool
}

// MARK: - ShareView

struct ShareView: View {
    // MARK: Lifecycle

    init(
        cachedChats: [ShareTargetChat],
        initialComment: String,
        attachments: [ShareAttachmentPreview],
        onSend: @escaping ([Int64], String) -> Void,
        onCancel: @escaping () -> Void,
    ) {
        self.cachedChats = cachedChats
        _comment = State(initialValue: initialComment)
        self.attachments = attachments
        self.onSend = onSend
        self.onCancel = onCancel
    }

    // MARK: Internal

    let cachedChats: [ShareTargetChat]
    let attachments: [ShareAttachmentPreview]
    let onSend: ([Int64], String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if !attachments.isEmpty {
                    Section {
                        ForEach(attachments) { attachment in
                            attachmentRow(attachment)
                        }
                    }
                }

                Section {
//                    TextField("Add a Caption", text: $comment, axis: .vertical)
                } footer: {
                    // The main app doesn't send this on its own the instant you tap Send here (see
                    // `ShareViewController.send` / `RootVM.processPendingShareRequests`) - a Share
                    // Extension can't launch its containing app, so the request just sits staged in
                    // the App Group container until SwiftTG itself is next opened or foregrounded.
                    Text("For now, open SwiftTG afterward to actually deliver this.")
                }

                if cachedChats.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Chats Available",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("Open SwiftTG at least once so it can remember your chats here."),
                        )
                    }
                } else {
                    Section {
                        ForEach(filteredChats) { chat in
                            chatRow(chat)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search chats")
            .navigationTitle("Share to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Send") {
                            isSending = true
                            onSend(Array(selectedChatIds), comment.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        .disabled(selectedChatIds.isEmpty)
                    }
                }
            }
        }
    }

    // MARK: Private

    @State private var comment: String
    @State private var isSending = false
    @State private var query = ""
    @State private var selectedChatIds = Set<Int64>()

    private var filteredChats: [ShareTargetChat] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return cachedChats }
        return cachedChats.filter { $0.title.localizedCaseInsensitiveContains(normalizedQuery) }
    }

    private func chatRow(_ chat: ShareTargetChat) -> some View {
        let isSelected = selectedChatIds.contains(chat.id)
        return Button {
            toggle(chat)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(chat.isSavedMessages
                        ? AnyShapeStyle(Color.accentColor.gradient)
                        : AnyShapeStyle(Color(telegramAvatarId: chat.id)))
                        .overlay {
                            if chat.isSavedMessages {
                                Image(systemName: "bookmark.fill")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            } else {
                                Text(String(chat.title.prefix(1)).uppercased())
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 40, height: 40)
                        .accessibilityHidden(true)

                Text(chat.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSending)
    }

    private func attachmentRow(_ attachment: ShareAttachmentPreview) -> some View {
        HStack(spacing: 12) {
            Group {
                if attachment.isImage, let thumbnail = Self.thumbnail(for: attachment.url) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)

            Text(attachment.name)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(attachment.isImage ? "Photo: \(attachment.name)" : "Document: \(attachment.name)")
    }

    /// Reads a downsized thumbnail directly from the file's image metadata rather than decoding the
    /// full-resolution image - Share Extensions run under a tight memory budget (~120MB), and this
    /// preview only ever needs to fill a 40x40 row.
    private static func thumbnail(for url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 80,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func toggle(_ chat: ShareTargetChat) {
        if !selectedChatIds.insert(chat.id).inserted {
            selectedChatIds.remove(chat.id)
        }
    }
}
