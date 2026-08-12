// ChatTopBannerView.swift

import SwiftUI

// MARK: - ChatTopBannerView

/// Keeps translation and pinned-message updates local to the top banner.
struct ChatTopBannerView: View {
    // MARK: Internal

    let chatVM: ChatVM
    let onShowAllPinnedMessages: () -> Void

    /// Pinned-message state is known as soon as the chat opens, while the translation banner only
    /// appears later - once background language detection resolves, seconds after the initial
    /// messages render (see `ChatVM.refreshDetectedChatLanguage`). Rendering the pinned banner
    /// first keeps its on-screen position stable when the translation banner shows up afterward:
    /// it's appended below instead of being inserted above and pushing an already-visible (and
    /// possibly VoiceOver-focused) banner down.
    var body: some View {
        if chatVM.currentPinnedMessage != nil {
            pinnedMessageBanner
            Divider()
        }
        if chatVM.showsChatTranslationBanner || chatVM.isChatTranslationEnabled {
            translationBanner
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
                StableIconButton(
                    systemImageName: "xmark",
                    accessibilityLabel: "Dismiss",
                    action: { chatVM.dismissChatTranslationSuggestion() },
                )
                .frame(width: 30, height: 30)
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

            StableIconButton(
                systemImageName: "chevron.right",
                accessibilityLabel: "Show All Pinned Messages",
                action: onShowAllPinnedMessages,
            )
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
