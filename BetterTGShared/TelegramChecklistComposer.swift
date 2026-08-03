// TelegramChecklistComposer.swift

import Foundation
import SwiftUI
import TDLibKit

// MARK: - TelegramChecklistDraftTask

struct TelegramChecklistDraftTask: Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), text: String = "") {
        self.id = id
        self.text = text
    }

    // MARK: Internal

    let id: UUID
    var text: String
}

// MARK: - TelegramChecklistDraft

struct TelegramChecklistDraft: Equatable, Sendable {
    // MARK: Internal

    static let maximumTaskCount = 30
    static let maximumTitleLength = 255
    static let maximumTaskLength = 100

    var title = ""
    var tasks = [TelegramChecklistDraftTask(), TelegramChecklistDraftTask()]

    var isValid: Bool {
        (try? inputMessageContent()) != nil
    }

    func inputMessageContent() throws -> InputMessageContent {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw TelegramChecklistDraftValidationError.titleRequired
        }
        guard trimmedTitle.count <= Self.maximumTitleLength else {
            throw TelegramChecklistDraftValidationError.titleTooLong
        }

        let nonemptyTasks = try tasks.enumerated().compactMap { index, task -> String? in
            let text = task.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count <= Self.maximumTaskLength else {
                throw TelegramChecklistDraftValidationError.taskTooLong(index: index + 1)
            }
            return text.isEmpty ? nil : text
        }
        guard !nonemptyTasks.isEmpty else {
            throw TelegramChecklistDraftValidationError.oneTaskRequired
        }
        guard nonemptyTasks.count <= Self.maximumTaskCount else {
            throw TelegramChecklistDraftValidationError.tooManyTasks
        }

        return .inputMessageChecklist(.init(checklist: InputChecklist(
            othersCanAddTasks: false,
            othersCanMarkTasksAsDone: false,
            tasks: nonemptyTasks.enumerated().map { index, text in
                InputChecklistTask(id: index + 1, text: plainText(text))
            },
            title: plainText(trimmedTitle),
        )))
    }

    mutating func addTask() {
        guard tasks.count < Self.maximumTaskCount else { return }
        tasks.append(TelegramChecklistDraftTask())
    }

    mutating func removeTask(id: UUID) {
        guard tasks.count > 1 else { return }
        tasks.removeAll { $0.id == id }
    }

    // MARK: Private

    private func plainText(_ text: String) -> FormattedText {
        FormattedText(
            entities: [],
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
        )
    }
}

// MARK: - TelegramChecklistDraftValidationError

enum TelegramChecklistDraftValidationError: Swift.Error, Equatable, LocalizedError {
    case titleRequired
    case titleTooLong
    case oneTaskRequired
    case tooManyTasks
    case taskTooLong(index: Int)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .titleRequired:
            "Enter a title."
        case .titleTooLong:
            "The title can have at most \(TelegramChecklistDraft.maximumTitleLength) characters."
        case .oneTaskRequired:
            "Enter at least one task."
        case .tooManyTasks:
            "A checklist can have at most \(TelegramChecklistDraft.maximumTaskCount) tasks."
        case .taskTooLong(let index):
            "Task \(index) can have at most \(TelegramChecklistDraft.maximumTaskLength) characters."
        }
    }
}

// MARK: - TelegramChecklistSending

enum TelegramChecklistSending {
    /// Checklists are a Telegram Premium feature; TDLib doesn't expose this as a chat permission
    /// the way poll-sending is, so it's checked against the current user instead.
    static func isAvailable(service: any TelegramService) async -> Bool {
        await (try? service.getMe())?.isPremium == true
    }

    @discardableResult static func send(
        draft: TelegramChecklistDraft,
        service: any TelegramService,
        chatId: Int64,
        replyToMessageId: Int64?,
    ) async throws -> Message {
        let content = try draft.inputMessageContent()
        let messages = try await TelegramMessageSending.send(
            service: service,
            chatId: chatId,
            contents: [content],
            replyTo: TelegramMessageSending.replyTo(messageId: replyToMessageId),
            onAccepted: { messages in
                service.mergeMessages(chatId: chatId, messages: messages)
            },
        )
        guard let message = messages.first else {
            throw TelegramChecklistSendingError.noMessageReturned
        }
        return message
    }
}

// MARK: - TelegramChecklistSendingError

private enum TelegramChecklistSendingError: Swift.Error, LocalizedError {
    case noMessageReturned

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .noMessageReturned:
            "Telegram accepted the checklist but didn't return the sent message."
        }
    }
}

// MARK: - TelegramChecklistComposerView

struct TelegramChecklistComposerView: View {
    // MARK: Lifecycle

    init(onSend: @escaping (TelegramChecklistDraft) async throws -> Void) {
        self.onSend = onSend
    }

    // MARK: Internal

    let onSend: (TelegramChecklistDraft) async throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $draft.title, axis: .vertical)
                }

                Section("Tasks") {
                    ForEach(Array(draft.tasks.enumerated()), id: \.element.id) { index, task in
                        HStack {
                            TextField("Task \(index + 1)", text: taskTextBinding(id: task.id), axis: .vertical)

                            if draft.tasks.count > 1 {
                                Button(
                                    "Remove task \(index + 1)",
                                    systemImage: "minus.circle",
                                    role: .destructive,
                                ) {
                                    draft.removeTask(id: task.id)
                                }
                            }
                        }
                    }

                    if draft.tasks.count < TelegramChecklistDraft.maximumTaskCount {
                        Button("Add Task", systemImage: "plus") {
                            draft.addTask()
                        }
                    }
                }

                if isSending {
                    ProgressView("Sending checklist")
                }

                if let feedbackMessage {
                    Section {
                        Text(feedbackMessage)
                            .foregroundStyle(.red)
                            .accessibilityFocused($feedbackIsFocused)
                    }
                }
            }
            .navigationTitle("New Checklist")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                            .disabled(isSending)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { send() }
                            .disabled(isSending || !draft.isValid)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    // MARK: Private

    @AccessibilityFocusState private var feedbackIsFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TelegramChecklistDraft()
    @State private var isSending = false
    @State private var feedbackMessage: String?

    private func taskTextBinding(id: UUID) -> Binding<String> {
        Binding(
            get: { draft.tasks.first(where: { $0.id == id })?.text ?? "" },
            set: { text in
                guard let index = draft.tasks.firstIndex(where: { $0.id == id }) else { return }
                draft.tasks[index].text = text
            },
        )
    }

    private func send() {
        feedbackMessage = nil
        feedbackIsFocused = false
        do {
            _ = try draft.inputMessageContent()
        } catch {
            feedbackMessage = telegramErrorDescription(error)
            feedbackIsFocused = true
            return
        }

        isSending = true
        Task {
            do {
                try await onSend(draft)
                dismiss()
            } catch {
                isSending = false
                feedbackMessage = telegramErrorDescription(error)
                feedbackIsFocused = true
            }
        }
    }
}
