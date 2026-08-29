// NewCallLinkView.swift

import SwiftUI
import TDLibKit

// MARK: - NewCallLinkView

struct NewCallLinkView: View {
    // MARK: Internal

    let service: any TelegramService

    var body: some View {
        Form {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Creating call link…")
                        Spacer()
                    }
                }
            } else if let call, let inviteURL {
                Section("Call Link") {
                    Text(inviteURL.absoluteString)
                        .textSelection(.enabled)
                    ShareLink(item: inviteURL) {
                        Label("Share Link", systemImage: "square.and.arrow.up")
                    }
                }

                Section {
                    Button("Start Call", systemImage: "phone.fill") {
                        Task { await startCall(inviteURL) }
                    }
                    Button("Reset Link", systemImage: "arrow.triangle.2.circlepath", role: .destructive) {
                        Task { await resetLink(call.id) }
                    }
                    Button("Delete Call Link", systemImage: "trash", role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                }
            }
        }
        .navigationTitle("Call Link")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task { await create() }
        .alert("Delete Call Link?", isPresented: $showsDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task { await deleteLink() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The link stops working and the unused call is discarded.")
        }
        .alert("Call Link Error", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var call: GroupCall?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showsDeleteConfirmation = false

    private var inviteURL: URL? {
        guard let link = call?.inviteLink, !link.isEmpty else { return nil }
        return URL(string: link)
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                }
            },
        )
    }

    @MainActor private func create() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let created = try await service.createGroupCall(joinParameters: nil)
            call = try await service.getGroupCall(groupCallId: created.groupCallId)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func startCall(_ inviteURL: URL) async {
        let joined = await TelegramCallSession.shared.joinConference(
            inviteLink: inviteURL.absoluteString,
            isMuted: false,
        )
        if joined {
            dismiss()
        } else {
            errorMessage = "The call couldn't be started. Check microphone access and make sure no other call is active."
        }
    }

    @MainActor private func resetLink(_ groupCallId: Int) async {
        do {
            _ = try await service.revokeGroupCallInviteLink(groupCallId: groupCallId)
            call = try await service.getGroupCall(groupCallId: groupCallId)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func deleteLink() async {
        guard let call else { return }
        do {
            _ = try await service.endGroupCall(groupCallId: call.id)
            dismiss()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
