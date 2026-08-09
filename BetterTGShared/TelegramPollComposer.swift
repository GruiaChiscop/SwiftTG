// TelegramPollComposer.swift

import Foundation
import SwiftUI
import TDLibKit

// MARK: - TelegramPollComposerKind

enum TelegramPollComposerKind: String, CaseIterable, Identifiable, Sendable {
    case poll
    case quiz

    // MARK: Internal

    var id: Self { self }

    var title: String {
        switch self {
        case .poll: "Poll"
        case .quiz: "Quiz"
        }
    }
}

// MARK: - TelegramPollDraftOption

struct TelegramPollDraftOption: Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

    init(id: UUID = UUID(), text: String = "") {
        self.id = id
        self.text = text
    }

    // MARK: Internal

    let id: UUID
    var text: String
}

// MARK: - TelegramPollDraft

struct TelegramPollDraft: Equatable, Sendable {
    // MARK: Internal

    static let maximumOptionCount = 10
    static let maximumQuestionLength = 255
    static let maximumDescriptionLength = 255
    static let maximumOptionLength = 100
    static let maximumExplanationLength = 200

    var kind = TelegramPollComposerKind.poll
    var question = ""
    var description = ""
    var options = [TelegramPollDraftOption(), TelegramPollDraftOption()]
    var correctOptionId: UUID?
    var explanation = ""
    var isAnonymous = true
    var allowsMultipleAnswers = false
    var allowsRevoting = false
    var shuffleOptions = false

    var isValid: Bool {
        (try? inputMessageContent()) != nil
    }

    func inputMessageContent() throws -> InputMessageContent {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            throw TelegramPollDraftValidationError.questionRequired
        }
        guard trimmedQuestion.count <= Self.maximumQuestionLength else {
            throw TelegramPollDraftValidationError.questionTooLong
        }

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedDescription.count <= Self.maximumDescriptionLength else {
            throw TelegramPollDraftValidationError.descriptionTooLong
        }

        let nonemptyOptions = try options.enumerated().compactMap { index, option -> (UUID, String)? in
            let text = option.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count <= Self.maximumOptionLength else {
                throw TelegramPollDraftValidationError.optionTooLong(index: index + 1)
            }
            return text.isEmpty ? nil : (option.id, text)
        }
        guard nonemptyOptions.count >= 2 else {
            throw TelegramPollDraftValidationError.twoOptionsRequired
        }
        guard nonemptyOptions.count <= Self.maximumOptionCount else {
            throw TelegramPollDraftValidationError.tooManyOptions
        }

        let inputType: InputPollType
        switch kind {
        case .poll:
            inputType = .inputPollTypeRegular(.init(allowAddingOptions: false))
        case .quiz:
            guard let correctOptionId,
                  let correctOptionIndex = nonemptyOptions.firstIndex(where: { $0.0 == correctOptionId })
            else {
                throw TelegramPollDraftValidationError.correctAnswerRequired
            }
            let trimmedExplanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedExplanation.count <= Self.maximumExplanationLength else {
                throw TelegramPollDraftValidationError.explanationTooLong
            }
            guard trimmedExplanation.count(where: { $0 == "\n" }) <= 2 else {
                throw TelegramPollDraftValidationError.explanationHasTooManyLines
            }
            inputType = .inputPollTypeQuiz(.init(
                correctOptionIds: [correctOptionIndex],
                explanation: plainText(trimmedExplanation),
                explanationMedia: nil,
            ))
        }

        return .inputMessagePoll(.init(
            allowsMultipleAnswers: kind == .poll && allowsMultipleAnswers,
            allowsRevoting: kind == .poll && allowsRevoting,
            closeDate: 0,
            countryCodes: [],
            description: plainText(trimmedDescription),
            hideResultsUntilCloses: false,
            isAnonymous: isAnonymous,
            isClosed: false,
            media: nil,
            membersOnly: false,
            openPeriod: 0,
            options: nonemptyOptions.map { option in
                InputPollOption(media: nil, text: plainText(option.1))
            },
            question: plainText(trimmedQuestion),
            shuffleOptions: shuffleOptions,
            type: inputType,
        ))
    }

    mutating func addOption() {
        guard options.count < Self.maximumOptionCount else { return }
        options.append(TelegramPollDraftOption())
    }

    mutating func removeOption(id: UUID) {
        guard options.count > 2 else { return }
        options.removeAll { $0.id == id }
        if correctOptionId == id {
            correctOptionId = nil
        }
    }

    // MARK: Private

    private func plainText(_ text: String) -> FormattedText {
        FormattedText(
            entities: [],
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
        )
    }
}

// MARK: - TelegramPollDraftValidationError

enum TelegramPollDraftValidationError: Swift.Error, Equatable, LocalizedError {
    case questionRequired
    case questionTooLong
    case descriptionTooLong
    case twoOptionsRequired
    case tooManyOptions
    case optionTooLong(index: Int)
    case correctAnswerRequired
    case explanationTooLong
    case explanationHasTooManyLines

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .questionRequired:
            "Enter a question."
        case .questionTooLong:
            "The question can have at most \(TelegramPollDraft.maximumQuestionLength) characters."
        case .descriptionTooLong:
            "The description can have at most \(TelegramPollDraft.maximumDescriptionLength) characters."
        case .twoOptionsRequired:
            "Enter at least two answer options."
        case .tooManyOptions:
            "A poll can have at most \(TelegramPollDraft.maximumOptionCount) answer options."
        case .optionTooLong(let index):
            "Option \(index) can have at most \(TelegramPollDraft.maximumOptionLength) characters."
        case .correctAnswerRequired:
            "Select the correct answer for the quiz."
        case .explanationTooLong:
            "The quiz explanation can have at most \(TelegramPollDraft.maximumExplanationLength) characters."
        case .explanationHasTooManyLines:
            "The quiz explanation can contain at most two line breaks."
        }
    }
}

// MARK: - TelegramPollSending

enum TelegramPollSending {
    // MARK: Internal

    static func isAvailable(service: any TelegramService, chatId: Int64) async -> Bool {
        do {
            try await validateDestination(service: service, chatId: chatId)
            return true
        } catch {
            return false
        }
    }

    @discardableResult static func send(
        draft: TelegramPollDraft,
        service: any TelegramService,
        chatId: Int64,
        replyToMessageId: Int64?,
        topicId: MessageTopic? = nil,
    ) async throws -> Message {
        let content = try draft.inputMessageContent()
        try await validateDestination(service: service, chatId: chatId)
        let messages = try await TelegramMessageSending.send(
            service: service,
            chatId: chatId,
            contents: [content],
            replyTo: TelegramMessageSending.replyTo(messageId: replyToMessageId),
            topicId: topicId,
            onAccepted: { messages in
                service.mergeMessages(chatId: chatId, messages: messages)
            },
        )
        guard let message = messages.first else {
            throw TelegramPollSendingError.noMessageReturned
        }
        return message
    }

    // MARK: Private

    private static func validateDestination(service: any TelegramService, chatId: Int64) async throws {
        let chat = try await service.getChat(chatId: chatId)
        switch chat.type {
        case .chatTypeBasicGroup(let type):
            let group = try await service.getBasicGroup(basicGroupId: type.basicGroupId)
            guard canSendPolls(
                defaultPermissions: chat.permissions,
                status: group.status,
                isChannel: false,
            ) else {
                throw TelegramPollSendingError.notAllowed
            }
        case .chatTypeSupergroup(let type):
            let supergroup = try await service.getSupergroup(supergroupId: type.supergroupId)
            if supergroup.isDirectMessagesGroup {
                throw TelegramPollSendingError.unsupportedChat
            }
            guard canSendPolls(
                defaultPermissions: chat.permissions,
                status: supergroup.status,
                isChannel: supergroup.isChannel,
            ) else {
                throw TelegramPollSendingError.notAllowed
            }
        case .chatTypePrivate(let type):
            let currentUser = try await service.getMe()
            guard type.userId != currentUser.id else { return }
            let user = try await service.getUser(userId: type.userId)
            guard case .userTypeBot = user.type else {
                throw TelegramPollSendingError.unsupportedChat
            }
        case .chatTypeSecret:
            throw TelegramPollSendingError.unsupportedChat
        }
    }

    private static func canSendPolls(
        defaultPermissions: ChatPermissions,
        status: ChatMemberStatus,
        isChannel: Bool,
    ) -> Bool {
        switch status {
        case .chatMemberStatusCreator:
            true
        case .chatMemberStatusAdministrator(let administrator):
            isChannel ? administrator.rights.canPostMessages : true
        case .chatMemberStatusMember:
            defaultPermissions.canSendPolls
        case .chatMemberStatusRestricted(let restricted):
            restricted.isMember && restricted.permissions.canSendPolls
        case .chatMemberStatusBanned, .chatMemberStatusLeft:
            false
        }
    }
}

// MARK: - TelegramPollSendingError

private enum TelegramPollSendingError: Swift.Error, LocalizedError {
    case noMessageReturned
    case notAllowed
    case unsupportedChat

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .noMessageReturned:
            "Telegram accepted the poll but didn't return the sent message."
        case .notAllowed:
            "You don't have permission to send polls in this chat."
        case .unsupportedChat:
            "Polls can be sent only to groups, channels, bots, or Saved Messages."
        }
    }
}

func telegramErrorDescription(_ error: Swift.Error) -> String {
    guard let error = error as? TDLibKit.Error else {
        return error.localizedDescription
    }
    guard error.code != 406 else {
        return "Telegram couldn't complete this action."
    }
    let message = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
    return message.isEmpty ? "Telegram error \(error.code)." : message
}

// MARK: - TelegramPollComposerView

struct TelegramPollComposerView: View {
    // MARK: Lifecycle

    init(onSend: @escaping (TelegramPollDraft) async throws -> Void) {
        self.onSend = onSend
    }

    // MARK: Internal

    let onSend: (TelegramPollDraft) async throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextField("Question", text: $draft.question, axis: .vertical)
                }

                Section("Answer Options") {
                    ForEach(Array(draft.options.enumerated()), id: \.element.id) { index, option in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Option \(index + 1)", text: optionTextBinding(id: option.id), axis: .vertical)

                            HStack {
                                if draft.kind == .quiz {
                                    Button(
                                        draft.correctOptionId == option.id
                                            ? "Option \(index + 1) is correct"
                                            : "Mark option \(index + 1) as correct",
                                        systemImage: draft.correctOptionId == option.id
                                            ? "checkmark.circle.fill"
                                            : "circle",
                                    ) {
                                        draft.correctOptionId = option.id
                                    }
                                    .accessibilityValue(
                                        draft.correctOptionId == option.id ? "Checked" : "Not checked",
                                    )
                                }

                                Spacer()

                                if draft.options.count > 2 {
                                    Button(
                                        "Remove option \(index + 1)",
                                        systemImage: "minus.circle",
                                        role: .destructive,
                                    ) {
                                        draft.removeOption(id: option.id)
                                    }
                                }
                            }
                        }
                    }

                    if draft.options.count < TelegramPollDraft.maximumOptionCount {
                        Button("Add Option", systemImage: "plus") {
                            draft.addOption()
                        }
                    }
                }

                Section("Settings") {
                    Picker("Type", selection: $draft.kind) {
                        ForEach(TelegramPollComposerKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }

                    Toggle("Anonymous Voting", isOn: $draft.isAnonymous)

                    if draft.kind == .poll {
                        Toggle("Allow Multiple Answers", isOn: $draft.allowsMultipleAnswers)
                        Toggle("Allow Revoting", isOn: $draft.allowsRevoting)
                    }

                    Toggle("Shuffle Options", isOn: $draft.shuffleOptions)
                }

                Section("Optional Description") {
                    TextField("Description", text: $draft.description, axis: .vertical)
                }

                if draft.kind == .quiz {
                    Section("Optional Quiz Explanation") {
                        TextField("Explanation shown after answering", text: $draft.explanation, axis: .vertical)
                    }
                }

                if isSending {
                    ProgressView("Sending poll")
                }

                if let feedbackMessage {
                    Section {
                        Text(feedbackMessage)
                            .foregroundStyle(.red)
                            .accessibilityFocused($feedbackIsFocused)
                    }
                }
            }
            .navigationTitle(draft.kind == .poll ? "New Poll" : "New Quiz")
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
    @State private var draft = TelegramPollDraft()
    @State private var isSending = false
    @State private var feedbackMessage: String?

    private func optionTextBinding(id: UUID) -> Binding<String> {
        Binding(
            get: { draft.options.first(where: { $0.id == id })?.text ?? "" },
            set: { text in
                guard let index = draft.options.firstIndex(where: { $0.id == id }) else { return }
                draft.options[index].text = text
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
