// ChatInfoProfileInformationSection.swift

import SwiftUI
import TDLibKit
import UIKit

/// Phone, username, birthdate, personal channel, bio/description, and (for bots) the privacy
/// policy.
struct ChatInfoProfileInformationSection: View {
    // MARK: Internal

    let info: TelegramChatInfoData

    var body: some View {
        if !info.usernames.isEmpty || info.phoneNumber != nil || info.birthdate != nil || info.about != nil
            || info.privacyPolicyURL != nil || info.usesPrivacyCommand || info.personalChatId != 0
        {
            Section {
                if let phoneNumber = info.phoneNumber {
                    LabeledContent("Phone", value: phoneNumber)
                        .textSelection(.enabled)
                        .contextMenu {
                            Button("Copy Phone Number", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = phoneNumber
                            }
                            if let phoneURL = URL(string: "tel:\(phoneNumber.filter { $0.isNumber || $0 == "+" })") {
                                Link("Call with Phone", destination: phoneURL)
                            }
                        }
                        .accessibilityAction(named: "Copy Phone Number") {
                            UIPasteboard.general.string = phoneNumber
                        }
                }

                if let username = info.usernames.first,
                   let url = URL(string: "https://t.me/\(username)")
                {
                    profileLinkRow(username: username, usernames: info.usernames, url: url)
                }

                if let birthdate = info.birthdate {
                    LabeledContent("Birthdate", value: birthdate)
                }

                if info.personalChatId != 0 {
                    Button {
                        ChatInfoNavigation.open(chatId: info.personalChatId, dismiss: dismiss)
                    } label: {
                        LabeledContent {
                            Text(info.personalChatTitle ?? "Open")
                        } label: {
                            Label("Channel", systemImage: "megaphone")
                        }
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if let about = info.about, !about.text.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(aboutLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(getAttributedString(from: about, .primary))
                    }
                    .textSelection(.enabled)
                }

                if let policy = info.privacyPolicyURL, let url = URL(string: policy) {
                    Link(destination: url) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                } else if info.usesPrivacyCommand {
                    Button {
                        sendPrivacyCommand()
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }
            }
        }
    }

    // MARK: Private

    @Environment(ChatVM.self) private var chatVM
    @Environment(\.dismiss) private var dismiss

    private var kind: CustomChat.ChatKind { chatVM.customChat.kind }

    private var aboutLabel: String {
        if info.isBot { return "Bot Info" }
        return kind == .group || kind == .channel ? "Description" : "Bio"
    }

    private func profileLinkRow(username: String, usernames: [String], url: URL) -> some View {
        let isPublicChat = kind == .group || kind == .channel
        let title = isPublicChat ? url.absoluteString : "@\(username)"
        let subtitle = linkSubtitle(usernames, isPublicChat: isPublicChat)
        let copyValue = isPublicChat ? url.absoluteString : "@\(username)"

        return Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: isPublicChat ? "link" : "at")
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.forward")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if copyValue != url.absoluteString {
                Button("Copy username", systemImage: "doc.on.doc") { UIPasteboard.general.string = copyValue }
            }
            Button("Copy Link", systemImage: "link") { UIPasteboard.general.string = url.absoluteString }
        }
        .accessibilityActions {
            Button("Copy Link", systemImage: "link") { UIPasteboard.general.string = url.absoluteString }
            if copyValue != url.absoluteString {
                Button("Copy username", systemImage: "doc.on.doc") { UIPasteboard.general.string = copyValue }
            }
        }
    }

    private func linkSubtitle(_ usernames: [String], isPublicChat: Bool) -> String {
        let label = isPublicChat ? "Link" : "Username"
        guard usernames.count > 1 else { return label }
        return "\(label). Also: \(usernames.dropFirst().map { "@\($0)" }.joined(separator: ", "))"
    }

    /// For a bot that exposes a `/privacy` command instead of a policy URL: mirrors Telegram's
    /// own behaviour of sending that command to the bot.
    private func sendPrivacyCommand() {
        let service = chatVM.service
        let chatId = chatVM.customChat.id
        dismiss()
        Task {
            do {
                _ = try await TelegramMessageSending.send(
                    service: service,
                    chatId: chatId,
                    contents: [TelegramMessageSending.textContent(FormattedText(entities: [], text: "/privacy"))],
                    replyTo: nil,
                )
            } catch {
                print("Sending /privacy to the bot failed: \(telegramErrorDescription(error))")
            }
        }
    }
}
