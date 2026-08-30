// TelegramReportFlow.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramReportRequest

/// What's being reported. An empty `messageIds` reports the whole chat / user. Used as the
/// `.sheet(item:)` payload that presents `TelegramReportView`.
struct TelegramReportRequest: Identifiable {
    let chatId: Int64
    let messageIds: [Int64]
    let title: String

    var id: String { "\(chatId)-\(messageIds.map(String.init).joined(separator: ","))" }
}

// MARK: - TelegramReportView

/// Drives TDLib's server-controlled `reportChat` flow: the server returns the reason options, may
/// ask for sub-options or free text, then confirms. The reason list is never hard-coded here.
struct TelegramReportView: View {
    // MARK: Internal

    let service: any TelegramService
    let request: TelegramReportRequest

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(request.title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(stage.isTerminal ? "Done" : "Cancel") { dismiss() }
                    }
                }
        }
        .task { submit(optionId: Data(), text: nil) }
    }

    // MARK: Private

    private enum Stage {
        case submitting
        case options(title: String, options: [ReportOption])
        case text(optionId: Data, isOptional: Bool)
        case messagesRequired
        case done
        case failed(String)

        // MARK: Internal

        var isTerminal: Bool {
            switch self {
            case .done, .failed, .messagesRequired: true
            default: false
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var stage = Stage.submitting
    @State private var detailsText = ""

    @ViewBuilder private var content: some View {
        switch stage {
        case .submitting:
            ProgressView().controlSize(.large)
        case .options(let title, let options):
            List {
                Section(title.isEmpty ? "What's wrong with it?" : title) {
                    ForEach(options) { option in
                        Button(option.text) { submit(optionId: option.id, text: nil) }
                            .foregroundStyle(.primary)
                    }
                }
            }
        case .text(let optionId, let isOptional):
            Form {
                Section("Add Details") {
                    TextField("Describe the problem", text: $detailsText, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Button("Submit Report") { submit(optionId: optionId, text: detailsText) }
                    if isOptional {
                        Button("Skip") { submit(optionId: optionId, text: "") }
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .messagesRequired:
            ContentUnavailableView(
                "Report a Message",
                systemImage: "flag",
                description: Text(
                    "Open the message you want to report in the chat and choose Report from its menu.",
                ),
            )
        case .done:
            ContentUnavailableView(
                "Report Sent",
                systemImage: "checkmark.circle",
                description: Text("Thanks. Telegram's moderators will review it."),
            )
        case .failed(let message):
            ContentUnavailableView(
                "Report Failed",
                systemImage: "exclamationmark.triangle",
                description: Text(message),
            )
        }
    }

    private func submit(optionId: Data, text: String?) {
        stage = .submitting
        Task {
            do {
                let result = try await service.reportChat(
                    chatId: request.chatId,
                    messageIds: request.messageIds.isEmpty ? nil : request.messageIds,
                    optionId: optionId,
                    text: text,
                )
                switch result {
                case .reportChatResultOk:
                    stage = .done
                case .reportChatResultOptionRequired(let value):
                    detailsText = ""
                    stage = .options(title: value.title, options: value.options)
                case .reportChatResultTextRequired(let value):
                    detailsText = ""
                    stage = .text(optionId: value.optionId, isOptional: value.isOptional)
                case .reportChatResultMessagesRequired:
                    stage = .messagesRequired
                }
            } catch {
                stage = .failed(telegramErrorDescription(error))
            }
        }
    }
}
