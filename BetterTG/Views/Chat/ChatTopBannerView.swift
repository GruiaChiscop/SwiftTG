// ChatTopBannerView.swift

import SwiftUI

// MARK: - ChatTopBannerView

/// Keeps translation and pinned-message updates local to the top banner.
struct ChatTopBannerView: View {
    // MARK: Internal

    let chatVM: ChatVM
    let onShowAllPinnedMessages: () -> Void

    var body: some View {
        if chatVM.showsChatTranslationBanner || chatVM.isChatTranslationEnabled {
            translationBanner
            Divider()
        } else if chatVM.currentPinnedMessage != nil {
            pinnedMessageBanner
            Divider()
        }
    }

    // MARK: Private

    private var detectedChatLanguageName: String {
        guard let code = chatVM.detectedChatLanguage else { return "" }
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    private var pinnedMessageSummary: String {
        guard let message = chatVM.currentPinnedMessage else { return "" }
        return telegramQuotedMessageExcerpt(telegramMessageContentDescription(message))
    }

    private var translationBanner: some View {
        HStack(spacing: 8) {
            StableTranslationBannerLabel(text: chatVM.isChatTranslationEnabled
                ? "Translated from \(detectedChatLanguageName)"
                : "Translate from \(detectedChatLanguageName)?")
                .frame(maxWidth: .infinity, alignment: .leading)

            if !chatVM.isChatTranslationEnabled {
                Button("Dismiss", systemImage: "xmark") {
                    chatVM.dismissChatTranslationSuggestion()
                }
                .labelStyle(.iconOnly)
            }

            Button(chatVM.isChatTranslationEnabled ? "Show Original" : "Translate") {
                if chatVM.isChatTranslationEnabled {
                    chatVM.disableChatTranslation()
                } else {
                    chatVM.enableChatTranslation()
                }
            }
            .font(chatVM.isChatTranslationEnabled ? .subheadline : .subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var pinnedMessageBanner: some View {
        HStack(spacing: 8) {
            Button {
                guard let message = chatVM.currentPinnedMessage else { return }
                chatVM.navigateToMessage(id: message.id)
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

            Button("Show All Pinned Messages", systemImage: "chevron.right", action: onShowAllPinnedMessages)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
