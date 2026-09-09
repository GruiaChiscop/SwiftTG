// TelegramDataPrivacySettings.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramContactsSyncPreference

/// Whether the app syncs device contacts to Telegram after login (iOS-only). Defaults to on,
/// matching Telegram-iOS's own default - the user turns it off in Data & Privacy to stop syncing.
enum TelegramContactsSyncPreference {
    // MARK: Internal

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    // MARK: Private

    private static let key = "TelegramContactsSyncPreference.isEnabled"
}

// MARK: - TelegramDataPrivacySettingsView

struct TelegramDataPrivacySettingsView: View {
    // MARK: Internal

    let service: any TelegramService

    var body: some View {
        Form {
            #if os(iOS)
            // Device-contacts sync goes through the global `PermissionsManager.shared` singleton,
            // which only ever wraps the iOS app's single TDLib client - macOS windows each own an
            // independent `MacSessionModel.service` with no equivalent bridge, so this toggle would
            // have nothing to actually turn on there.
            Section {
                Toggle("Sync Contacts", isOn: syncContactsBinding)
                    .disabled(isSyncingContacts)
            } footer: {
                Text(
                    "When enabled, SwiftTG sends names and phone numbers from this device to Telegram to find people you know.",
                )
            }
            #endif

            Section {
                Button("Delete Synced Contacts", role: .destructive) {
                    confirmsDeleteContacts = true
                }
                .disabled(isDeletingContacts)
            }

            Section {
                Toggle("Suggest Frequent Contacts", isOn: suggestFrequentContactsBinding)
                    .disabled(!hasLoadedFrequentContactsSetting || isSavingFrequentContactsSetting)
                Button("Delete Frequent Contacts Data", role: .destructive) {
                    confirmsDeleteFrequentContacts = true
                }
                .disabled(isDeletingFrequentContacts)
            } footer: {
                Text("Display people you message frequently at the top of the search section for quick access.")
            }

            Section {
                Button("Delete All Cloud Drafts", role: .destructive) {
                    confirmsDeleteDrafts = true
                }
                .disabled(isDeletingDrafts)
            }

            Section {
                Button("Clear Payment & Shipping Info", role: .destructive) {
                    confirmsClearPaymentInfo = true
                }
                .disabled(isClearingPaymentInfo)
            } footer: {
                Text(
                    "You can delete your shipping info and instruct all payment providers to remove your saved " +
                        "credit cards. Telegram never stores your credit card data.",
                )
            }
        }
        .navigationTitle("Data Settings")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                await loadFrequentContactsSetting()
            }
            .alert(
                "Delete synced contacts?",
                isPresented: $confirmsDeleteContacts,
            ) {
                Button("Delete", role: .destructive) { Task { await deleteSyncedContacts() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This will remove your contacts from the Telegram servers. " +
                        "If \"Sync Contacts\" is enabled, contacts will be re-synced.",
                )
            }
            .alert(
                "Delete frequent contacts data?",
                isPresented: $confirmsDeleteFrequentContacts,
            ) {
                Button("Delete", role: .destructive) { Task { await deleteFrequentContacts() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This will delete all data about the people you message frequently as well the inline bots you are likely to use.",
                )
            }
            .alert(
                "Delete all cloud drafts?",
                isPresented: $confirmsDeleteDrafts,
            ) {
                Button("Delete", role: .destructive) { Task { await deleteAllCloudDrafts() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Drafts will be removed from all your chats.")
            }
            .alert(
                "Clear payment & shipping info?",
                isPresented: $confirmsClearPaymentInfo,
            ) {
                Button("Clear Payment Info", role: .destructive) {
                    Task { await clearPaymentInfo(paymentInfo: true, shippingInfo: false) }
                }
                Button("Clear Shipping Info", role: .destructive) {
                    Task { await clearPaymentInfo(paymentInfo: false, shippingInfo: true) }
                }
                Button("Clear Both", role: .destructive) {
                    Task { await clearPaymentInfo(paymentInfo: true, shippingInfo: true) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(statusMessage ?? "", isPresented: statusMessageIsPresented) {
                Button("OK") {}
            }
            .alert("Couldn't Complete Request", isPresented: errorIsPresented) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    // MARK: Private

    private static let frequentContactsOptionName = "disable_top_chats"
    private static let frequentContactsCategories: [TopChatCategory] = [
        .topChatCategoryUsers,
        .topChatCategoryInlineBots,
    ]

    @State private var confirmsClearPaymentInfo = false
    @State private var confirmsDeleteContacts = false
    @State private var confirmsDeleteDrafts = false
    @State private var confirmsDeleteFrequentContacts = false
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var hasLoadedFrequentContactsSetting = false
    @State private var isClearingPaymentInfo = false
    @State private var isDeletingContacts = false
    @State private var isDeletingDrafts = false
    @State private var isDeletingFrequentContacts = false
    @State private var isSavingFrequentContactsSetting = false
    #if os(iOS)
    @State private var isSyncingContacts = false
    @State private var syncContactsEnabled = TelegramContactsSyncPreference.isEnabled
    #endif
    @State private var statusMessage: String?
    @State private var suggestsFrequentContacts = true

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

    private var statusMessageIsPresented: Binding<Bool> {
        Binding(
            get: { statusMessage != nil },
            set: { isPresented in
                if !isPresented {
                    statusMessage = nil
                }
            },
        )
    }

    #if os(iOS)
    private var syncContactsBinding: Binding<Bool> {
        Binding(
            get: { syncContactsEnabled },
            set: { newValue in
                syncContactsEnabled = newValue
                TelegramContactsSyncPreference.isEnabled = newValue
                guard newValue else { return }
                Task { await syncContactsNow() }
            },
        )
    }
    #endif

    private var suggestFrequentContactsBinding: Binding<Bool> {
        Binding(
            get: { suggestsFrequentContacts },
            set: { newValue in
                let previousValue = suggestsFrequentContacts
                suggestsFrequentContacts = newValue
                isSavingFrequentContactsSetting = true
                Task {
                    defer { isSavingFrequentContactsSetting = false }
                    do {
                        _ = try await service.setOption(
                            name: Self.frequentContactsOptionName,
                            value: .optionValueBoolean(OptionValueBoolean(value: !newValue)),
                        )
                    } catch {
                        suggestsFrequentContacts = previousValue
                        errorMessage = telegramErrorDescription(error)
                    }
                }
            },
        )
    }

    @MainActor private func loadFrequentContactsSetting() async {
        defer { hasLoadedFrequentContactsSetting = true }
        guard case .optionValueBoolean(let disabled) = try? await service.getOption(
            name: Self.frequentContactsOptionName,
        ) else { return }
        suggestsFrequentContacts = !disabled.value
    }

    #if os(iOS)
    @MainActor private func syncContactsNow() async {
        isSyncingContacts = true
        defer { isSyncingContacts = false }
        let didSync = await PermissionsManager.shared.requestAndSyncContacts()
        guard !didSync else { return }
        syncContactsEnabled = false
        TelegramContactsSyncPreference.isEnabled = false
        errorMessage = PermissionsManager.shared.contactsAuthorizationStatus == .denied
            ? "Contacts access is off. You can allow it in the Settings app."
            : "SwiftTG couldn't sync your contacts. Please try again."
    }
    #endif

    @MainActor private func deleteSyncedContacts() async {
        isDeletingContacts = true
        defer { isDeletingContacts = false }
        do {
            let contacts = try await service.getContacts()
            _ = try await service.removeContacts(userIds: contacts.userIds)
            statusMessage = "All synced contacts deleted."
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func deleteFrequentContacts() async {
        isDeletingFrequentContacts = true
        defer { isDeletingFrequentContacts = false }
        do {
            for category in Self.frequentContactsCategories {
                let chats = try await service.getTopChats(category: category, limit: 30)
                for chatId in chats.chatIds {
                    _ = try await service.removeTopChat(category: category, chatId: chatId)
                }
            }
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func deleteAllCloudDrafts() async {
        isDeletingDrafts = true
        defer { isDeletingDrafts = false }
        do {
            let mainChatIds = try await service.getChats(chatList: .chatListMain, limit: 200).chatIds
            let archivedChatIds = try await service.getChats(chatList: .chatListArchive, limit: 200).chatIds
            let chatIds = mainChatIds + archivedChatIds
            let draftChatIds = await chatIds.concurrentCompactMap { chatId -> Int64? in
                guard let chat = try? await service.getChat(chatId: chatId), chat.draftMessage != nil else {
                    return nil
                }
                return chatId
            }
            for chatId in draftChatIds {
                _ = try await service.setChatDraftMessage(chatId: chatId, draftMessage: nil, topicId: nil)
            }
            statusMessage = "All cloud drafts deleted."
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func clearPaymentInfo(paymentInfo: Bool, shippingInfo: Bool) async {
        isClearingPaymentInfo = true
        defer { isClearingPaymentInfo = false }
        do {
            if paymentInfo {
                _ = try await service.deleteSavedCredentials()
            }
            if shippingInfo {
                _ = try await service.deleteSavedOrderInfo()
            }
            statusMessage =
                switch (paymentInfo, shippingInfo) {
                case (true, true): "Payment and shipping info cleared."
                case (true, false): "Payment info cleared."
                case (false, true): "Shipping info cleared."
                case (false, false): ""
                }
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
