// TelegramChecklist.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramChecklistTaskPresentation

struct TelegramChecklistTaskPresentation: Equatable, Identifiable, Sendable {
    let taskId: Int
    let text: String
    let isDone: Bool

    var id: Int { taskId }
}

// MARK: - TelegramChecklistPresentation

struct TelegramChecklistPresentation: Equatable, Sendable {
    // MARK: Lifecycle

    init(_ content: MessageChecklist) {
        let checklist = content.list
        self.title = checklist.title.text
        self.tasks = checklist.tasks.map { task in
            TelegramChecklistTaskPresentation(
                taskId: task.id,
                text: task.text.text,
                isDone: task.completedBy != nil,
            )
        }
    }

    // MARK: Internal

    let title: String
    let tasks: [TelegramChecklistTaskPresentation]

    var doneCount: Int { tasks.count(where: \.isDone) }

    var progressDescription: String {
        "\(doneCount) of \(tasks.count) done"
    }

    var contentDescription: String {
        var parts = ["Checklist: \(title)"]
        if !tasks.isEmpty {
            let taskDescriptions = tasks.map { "\($0.text), \($0.isDone ? "done" : "not done")" }
            parts.append("Tasks: " + taskDescriptions.joined(separator: "; "))
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - TelegramChecklistView

struct TelegramChecklistView<MessageHeader: View>: View {
    // MARK: Lifecycle

    init(
        content: MessageChecklist,
        message: Message,
        canMarkTasksAsDone: Bool,
        service: any TelegramService,
        @ViewBuilder messageHeader: () -> MessageHeader,
    ) {
        self.content = content
        self.message = message
        self.canMarkTasksAsDone = canMarkTasksAsDone
        self.service = service
        self.messageHeader = messageHeader()
    }

    // MARK: Internal

    let content: MessageChecklist
    let message: Message
    let canMarkTasksAsDone: Bool
    let service: any TelegramService
    let messageHeader: MessageHeader

    var body: some View {
        let presentation = TelegramChecklistPresentation(content)
        VStack(alignment: .leading, spacing: 10) {
            messageHeader
                .font(.headline)

            Text(presentation.title)
                .font(.subheadline.weight(.semibold))

            ForEach(presentation.tasks) { task in
                taskRow(task)
            }

            Text(presentation.progressDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityFocused($errorIsFocused)
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
        .padding(10)
    }

    // MARK: Private

    @AccessibilityFocusState private var errorIsFocused: Bool
    @State private var togglingTaskIds = Set<Int>()
    @State private var errorMessage: String?

    @ViewBuilder private func taskRow(_ task: TelegramChecklistTaskPresentation) -> some View {
        if canMarkTasksAsDone {
            Button {
                toggle(task)
            } label: {
                taskLabel(task)
            }
            .buttonStyle(.plain)
            .disabled(togglingTaskIds.contains(task.taskId))
            .accessibilityValue(task.isDone ? "Checked" : "Not checked")
        } else {
            taskLabel(task)
                .accessibilityElement(children: .combine)
                .accessibilityValue(task.isDone ? "Checked" : "Not checked")
        }
    }

    private func taskLabel(_ task: TelegramChecklistTaskPresentation) -> some View {
        HStack {
            Image(systemName: task.isDone ? "checkmark.square.fill" : "square")
                .foregroundStyle(task.isDone ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            Text(task.text)
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
        }
        .contentShape(.rect)
    }

    private func toggle(_ task: TelegramChecklistTaskPresentation) {
        guard !togglingTaskIds.contains(task.taskId) else { return }
        togglingTaskIds.insert(task.taskId)
        errorMessage = nil
        errorIsFocused = false
        Task {
            defer { togglingTaskIds.remove(task.taskId) }
            do {
                _ = try await service.markChecklistTasksAsDone(
                    chatId: message.chatId,
                    markedAsDoneTaskIds: task.isDone ? [] : [task.taskId],
                    markedAsNotDoneTaskIds: task.isDone ? [task.taskId] : [],
                    messageId: message.id,
                )
            } catch {
                errorMessage = "Task couldn't be updated: \(telegramErrorDescription(error))"
                await Task.yield()
                errorIsFocused = true
            }
        }
    }
}
