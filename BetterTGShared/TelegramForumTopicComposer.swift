// TelegramForumTopicComposer.swift

import SwiftUI
import TDLibKit

extension Color {
    /// Unpacks a forum topic icon's packed 0xRRGGBB color (`ForumTopicIcon.color`) into a `Color`.
    init(topicIconRGB rgb: Int) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1,
        )
    }
}

// MARK: - TelegramForumTopicDraft

struct TelegramForumTopicDraft: Sendable {
    var name: String
    var iconColor: Int
    var iconCustomEmojiId: TdInt64
}

// MARK: - TelegramForumTopicSending

enum TelegramForumTopicSending {
    /// Telegram-iOS's fixed forum-icon color palette - topic icons aren't arbitrary RGB, they're
    /// chosen from this specific set.
    static let iconColors = [0x6FB9F0, 0xFFD67E, 0xCB86DB, 0x8EEE98, 0xFF93B2, 0xFB6F5F]

    static func create(
        service: any TelegramService,
        chatId: Int64,
        draft: TelegramForumTopicDraft,
    ) async throws -> ForumTopicInfo {
        try await service.createForumTopic(
            chatId: chatId,
            icon: ForumTopicIcon(color: draft.iconColor, customEmojiId: draft.iconCustomEmojiId),
            isNameImplicit: false,
            name: draft.name,
        )
    }

    static func edit(
        service: any TelegramService,
        chatId: Int64,
        forumTopicId: Int,
        draft: TelegramForumTopicDraft,
    ) async throws {
        _ = try await service.editForumTopic(
            chatId: chatId,
            editIconCustomEmoji: true,
            forumTopicId: forumTopicId,
            iconCustomEmojiId: draft.iconCustomEmojiId,
            name: draft.name,
        )
    }
}

// MARK: - TelegramForumTopicComposerView

/// Create/edit sheet for a forum topic's name and icon - `existingTopic == nil` means create.
/// Generic over `IconPreview` (rather than rendering stickers itself) because sticker rendering
/// (`TelegramStickerView`) lives in the iOS-only app target and isn't visible from here - the
/// same split `TelegramStickerPickerView` already uses for its own preview closure.
struct TelegramForumTopicComposerView<IconPreview: View>: View {
    // MARK: Lifecycle

    init(
        service: any TelegramService,
        existingTopic: ForumTopicInfo?,
        onSave: @escaping (TelegramForumTopicDraft) async throws -> Void,
        @ViewBuilder iconPreview: @escaping (Sticker) -> IconPreview,
    ) {
        self.service = service
        self.existingTopic = existingTopic
        self.onSave = onSave
        self.iconPreview = iconPreview
        self._name = State(initialValue: existingTopic?.name ?? "")
        self._iconColor = State(
            initialValue: existingTopic?.icon.color ?? TelegramForumTopicSending.iconColors[0],
        )
        self._iconCustomEmojiId = State(initialValue: existingTopic?.icon.customEmojiId ?? 0)
    }

    // MARK: Internal

    let service: any TelegramService
    let existingTopic: ForumTopicInfo?
    let onSave: (TelegramForumTopicDraft) async throws -> Void
    let iconPreview: (Sticker) -> IconPreview

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Topic Name", text: $name)
                        .autocorrectionDisabled(false)
                }

                Section("Icon Color") {
                    colorPicker
                }

                Section("Icon") {
                    iconPicker
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existingTopic == nil ? "New Topic" : "Edit Topic")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button("Save", action: save)
                                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .task { await loadDefaultIcons() }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var iconColor: Int
    @State private var iconCustomEmojiId: TdInt64
    @State private var defaultIcons = [Sticker]()
    @State private var isLoadingIcons = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var colorPicker: some View {
        HStack(spacing: 14) {
            ForEach(TelegramForumTopicSending.iconColors, id: \.self) { color in
                Button {
                    withAnimation { iconColor = color }
                } label: {
                    Circle()
                        .fill(Color(topicIconRGB: color))
                        .frame(width: 32, height: 32)
                        .overlay {
                            if color == iconColor {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color")
                .accessibilityAddTraits(color == iconColor ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var iconPicker: some View {
        if isLoadingIcons {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation { iconCustomEmojiId = 0 }
                    } label: {
                        Circle()
                            .fill(Color(topicIconRGB: iconColor).opacity(0.2))
                            .frame(width: 44, height: 44)
                            .overlay {
                                Text(String(name.first ?? "#"))
                                    .font(.headline)
                                    .foregroundStyle(Color(topicIconRGB: iconColor))
                            }
                            .overlay {
                                if iconCustomEmojiId.rawValue == 0 {
                                    Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("No icon, use initial")
                    .accessibilityAddTraits(iconCustomEmojiId.rawValue == 0 ? .isSelected : [])

                    ForEach(defaultIcons, id: \.id) { icon in
                        Button {
                            withAnimation { iconCustomEmojiId = icon.id }
                        } label: {
                            iconPreview(icon)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if icon.id == iconCustomEmojiId {
                                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(icon.emoji.isEmpty ? "Icon" : "Icon \(icon.emoji)")
                        .accessibilityAddTraits(icon.id == iconCustomEmojiId ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func loadDefaultIcons() async {
        guard defaultIcons.isEmpty, !isLoadingIcons else { return }
        isLoadingIcons = true
        defer { isLoadingIcons = false }
        defaultIcons = await (try? service.getForumTopicDefaultIcons())?.stickers ?? []
    }

    private func save() {
        guard !isSaving else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        errorMessage = nil

        Task {
            defer { isSaving = false }
            do {
                try await onSave(TelegramForumTopicDraft(
                    name: trimmedName,
                    iconColor: iconColor,
                    iconCustomEmojiId: iconCustomEmojiId,
                ))
                dismiss()
            } catch {
                errorMessage = "Couldn't save this topic: \(telegramErrorDescription(error))"
            }
        }
    }
}
