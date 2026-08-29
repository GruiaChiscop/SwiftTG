// VideoChatScheduleView.swift

import SwiftUI
import TDLibKit

// MARK: - VideoChatScheduleView

struct VideoChatScheduleView: View {
    // MARK: Internal

    let chatId: Int64
    let service: any TelegramService
    let onCreated: (GroupCall) -> Void

    var body: some View {
        Form {
            Section {
                TextField("Title (optional)", text: $title)
                DatePicker(
                    "Starts",
                    selection: $startDate,
                    in: minimumDate...maximumDate,
                    displayedComponents: [.date, .hourAndMinute],
                )
            } footer: {
                Text("Telegram allows scheduling between 10 seconds and 8 days from now.")
            }
        }
        .navigationTitle("Schedule Voice Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Schedule") {
                    Task { await create() }
                }
                .disabled(isCreating)
            }
        }
        .alert("Couldn't Schedule Voice Chat", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var isCreating = false
    @State private var startDate = Foundation.Date().addingTimeInterval(3600)
    @State private var title = ""

    private var minimumDate: Foundation.Date { Foundation.Date().addingTimeInterval(10) }
    private var maximumDate: Foundation.Date { Foundation.Date().addingTimeInterval(8 * 24 * 60 * 60) }

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
        isCreating = true
        defer { isCreating = false }
        do {
            let created = try await service.createVideoChat(
                chatId: chatId,
                isRtmpStream: false,
                startDate: Int(startDate.timeIntervalSince1970),
                title: title,
            )
            let call = try await service.getGroupCall(groupCallId: created.id)
            onCreated(call)
            dismiss()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
