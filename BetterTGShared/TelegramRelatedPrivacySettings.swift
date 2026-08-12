// TelegramRelatedPrivacySettings.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramRelatedPrivacySettingsSection

struct TelegramRelatedPrivacySettingsSection: View {
    // MARK: Internal

    let service: any TelegramService
    let setting: UserPrivacySetting

    var body: some View {
        Group {
            if let relatedItem {
                Section {
                    Button {
                        presentedItem = relatedItem
                    } label: {
                        LabeledContent(
                            relatedItem.title,
                            value: relatedRules.map { TelegramPrivacyOption(rules: $0).title } ?? "Loading…",
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(relatedRules == nil)
                } footer: {
                    if let footer = relatedItem.footer {
                        Text(footer)
                    }
                }
            }
        }
        .task(id: relatedItem?.id) {
            await loadRelatedRules()
        }
        .sheet(item: $presentedItem) { item in
            if let relatedRules {
                TelegramPrivacyDetailView(
                    service: service,
                    item: item,
                    rules: relatedRules,
                ) { updatedRules in
                    self.relatedRules = updatedRules
                }
            }
        }
        .alert("Couldn't Load Related Privacy Setting", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var presentedItem: TelegramPrivacyItem?
    @State private var relatedRules: UserPrivacySettingRules?

    private var relatedItem: TelegramPrivacyItem? {
        switch setting {
        case .userPrivacySettingAllowCalls:
            TelegramPrivacyItem(
                setting: .userPrivacySettingAllowPeerToPeerCalls,
                title: "Peer-to-Peer",
                footer: "Disabling peer-to-peer calls relays calls through Telegram servers to avoid revealing your IP address.",
            )
        case .userPrivacySettingShowPhoneNumber:
            TelegramPrivacyItem(
                setting: .userPrivacySettingAllowFindingByPhoneNumber,
                title: "Who Can Find Me By My Number",
                footer: "People who add your number to their contacts can find you on Telegram only if allowed here.",
                availableOptions: [.everybody, .myContacts],
            )
        default:
            nil
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            },
        )
    }

    @MainActor private func loadRelatedRules() async {
        guard !hasLoaded, let relatedItem else { return }
        hasLoaded = true
        do {
            relatedRules = try await service.getUserPrivacySettingRules(setting: relatedItem.setting)
        } catch is CancellationError {
            hasLoaded = false
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
