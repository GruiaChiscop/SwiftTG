// TelegramPoll.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramPollOptionPresentation

struct TelegramPollOptionPresentation: Equatable, Identifiable, Sendable {
    let position: Int
    let text: String
    let votePercentage: Int
    let voterCount: Int
    let isChosen: Bool
    let isBeingChosen: Bool
    let isCorrect: Bool?

    var id: Int { position }
}

// MARK: - TelegramPollPresentation

struct TelegramPollPresentation: Equatable, Sendable {
    // MARK: Lifecycle

    init(_ content: MessagePoll) {
        let poll = content.poll
        let quizMode: Bool
        let quizExplanation: String?
        let correctPositions: Set<Int>
        switch poll.type {
        case .pollTypeRegular:
            quizMode = false
            quizExplanation = nil
            correctPositions = []
        case .pollTypeQuiz(let quiz):
            quizMode = true
            quizExplanation = quiz.explanation.text.isEmpty ? nil : quiz.explanation.text
            correctPositions = Set(quiz.correctOptionIds)
        }

        let naturalOrder = Array(poll.options.indices)
        let requestedOrder = poll.optionOrder.filter { poll.options.indices.contains($0) }
        let uniqueRequestedOrder = requestedOrder.reduce(into: [Int]()) { result, position in
            if !result.contains(position) {
                result.append(position)
            }
        }
        let displayOrder = uniqueRequestedOrder + naturalOrder.filter { !uniqueRequestedOrder.contains($0) }
        self.options = displayOrder.map { position in
            let option = poll.options[position]
            return TelegramPollOptionPresentation(
                position: position,
                text: option.text.text,
                votePercentage: option.votePercentage,
                voterCount: option.voterCount,
                isChosen: option.isChosen,
                isBeingChosen: option.isBeingChosen,
                isCorrect: quizMode ? correctPositions.contains(position) : nil,
            )
        }

        self.question = poll.question.text
        self.description = content.description.text
        self.isQuiz = quizMode
        self.isAnonymous = poll.isAnonymous
        self.canGetVoters = poll.canGetVoters
        self.canSeeResults = poll.canSeeResults
        self.isClosed = poll.isClosed
        self.allowsMultipleAnswers = poll.allowsMultipleAnswers
        self.allowsRevoting = poll.allowsRevoting
        self.totalVoterCount = poll.totalVoterCount
        self.explanation = quizExplanation
        self.voteRestriction = telegramPollVoteRestrictionDescription(poll.voteRestrictionReason)
    }

    // MARK: Internal

    let question: String
    let description: String
    let isQuiz: Bool
    let isAnonymous: Bool
    let canGetVoters: Bool
    let canSeeResults: Bool
    let isClosed: Bool
    let allowsMultipleAnswers: Bool
    let allowsRevoting: Bool
    let totalVoterCount: Int
    let explanation: String?
    let voteRestriction: String?
    let options: [TelegramPollOptionPresentation]

    var chosenOptionPositions: Set<Int> {
        Set(options.filter(\.isChosen).map(\.position))
    }

    var hasVoted: Bool { !chosenOptionPositions.isEmpty }

    var resultsVisible: Bool { canSeeResults }

    var canVote: Bool {
        !isClosed && voteRestriction == nil && (!hasVoted || allowsRevoting)
    }

    var typeDescription: String {
        var parts = [isQuiz ? "Quiz" : "Poll"]
        if isAnonymous {
            parts.insert("Anonymous", at: 0)
        }
        if isClosed {
            parts.append("closed")
        } else if allowsMultipleAnswers {
            parts.append("multiple answers allowed")
        }
        return parts.joined(separator: ", ")
    }

    var contentDescription: String {
        var parts = ["\(isQuiz ? "Quiz" : "Poll"): \(question)"]
        if !options.isEmpty {
            parts.append("Options: " + options.map(\.text).joined(separator: "; "))
        }
        if resultsVisible {
            parts.append(telegramPollVoteCountDescription(totalVoterCount))
        }
        if isClosed {
            parts.append("Closed")
        }
        return parts.joined(separator: ". ")
    }
}

func telegramPollSelection(
    afterToggling position: Int,
    in selection: Set<Int>,
    allowsMultipleAnswers: Bool,
) -> Set<Int> {
    guard allowsMultipleAnswers else { return [position] }
    var updated = selection
    if updated.contains(position) {
        updated.remove(position)
    } else {
        updated.insert(position)
    }
    return updated
}

func telegramPollVoteCountDescription(_ count: Int) -> String {
    "\(count) \(count == 1 ? "vote" : "votes")"
}

func telegramPollVoteRestrictionDescription(_ reason: PollVoteRestrictionReason?) -> String? {
    switch reason {
    case nil:
        nil
    case .pollVoteRestrictionReasonClosed:
        "Voting is closed"
    case .pollVoteRestrictionReasonYetUnsent:
        "Voting will be available after the poll is sent"
    case .pollVoteRestrictionReasonScheduled:
        "Voting will be available after the scheduled poll is sent"
    case .pollVoteRestrictionReasonCountryRestricted:
        "Voting isn't available in your country"
    case .pollVoteRestrictionReasonMembershipRequired:
        "You must be a member of the chat for at least one day to vote"
    case .pollVoteRestrictionReasonOther:
        "Voting isn't available"
    }
}

extension PollType {
    var isQuiz: Bool {
        if case .pollTypeQuiz = self {
            return true
        }
        return false
    }
}

// MARK: - TelegramPollView

struct TelegramPollView: View {
    // MARK: Lifecycle

    init(content: MessagePoll, message: Message, service: any TelegramService) {
        self.content = content
        self.message = message
        self.service = service
        _selection = State(initialValue: TelegramPollPresentation(content).chosenOptionPositions)
    }

    // MARK: Internal

    let content: MessagePoll
    let message: Message
    let service: any TelegramService

    var body: some View {
        let presentation = TelegramPollPresentation(content)
        VStack(alignment: .leading, spacing: 10) {
            Text(presentation.question)
                .font(.headline)
                .accessibilityHidden(true)

            Text(presentation.typeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !presentation.description.isEmpty {
                Text(presentation.description)
            }

            ForEach(presentation.options) { option in
                optionControl(option, presentation: presentation)
            }

            if presentation.canVote {
                Button(presentation.hasVoted ? "Update Vote" : "Vote") {
                    submit(Array(selection).sorted())
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    selection.isEmpty
                        || selection == presentation.chosenOptionPositions
                        || isSubmitting,
                )
            }

            if presentation.hasVoted, presentation.allowsRevoting, presentation.canVote {
                Button("Retract vote") { submit([]) }
                    .disabled(isSubmitting)
            }

            if let restriction = presentation.voteRestriction, !presentation.isClosed {
                Text(restriction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if presentation.resultsVisible {
                Text(telegramPollVoteCountDescription(presentation.totalVoterCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let explanation = presentation.explanation, presentation.resultsVisible {
                Text("Explanation: \(explanation)")
                    .font(.callout)
            }

            if !presentation.isAnonymous {
                Button("View Votes") { showsVoters = true }
                    .disabled(!presentation.canGetVoters)
            }

            if isSubmitting {
                ProgressView("Submitting vote")
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityFocused($errorIsFocused)
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
        .padding(10)
        .onChange(of: presentation.chosenOptionPositions) { _, chosenPositions in
            guard !isSubmitting else { return }
            selection = chosenPositions
        }
        .sheet(isPresented: $showsVoters) {
            TelegramPollVotersView(content: content, message: message, service: service)
        }
    }

    // MARK: Private

    @AccessibilityFocusState private var errorIsFocused: Bool
    @State private var selection: Set<Int>
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showsVoters = false

    @ViewBuilder private func optionControl(
        _ option: TelegramPollOptionPresentation,
        presentation: TelegramPollPresentation,
    ) -> some View {
        let isSelected = selection.contains(option.position)
        if presentation.canVote {
            Button {
                selection = telegramPollSelection(
                    afterToggling: option.position,
                    in: selection,
                    allowsMultipleAnswers: presentation.allowsMultipleAnswers,
                )
            } label: {
                optionLabel(option, isSelected: isSelected, presentation: presentation)
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .accessibilityValue(optionAccessibilityValue(
                option,
                isSelected: isSelected,
                presentation: presentation,
            ))
        } else {
            optionLabel(option, isSelected: isSelected, presentation: presentation)
                .accessibilityElement(children: .combine)
                .accessibilityValue(optionAccessibilityValue(
                    option,
                    isSelected: isSelected,
                    presentation: presentation,
                ))
        }
    }

    private func optionLabel(
        _ option: TelegramPollOptionPresentation,
        isSelected: Bool,
        presentation: TelegramPollPresentation,
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(optionColor(option, isSelected: isSelected, presentation: presentation))
                    .accessibilityHidden(true)
                Text(option.text)
                Spacer(minLength: 12)
                if presentation.resultsVisible {
                    Text("\(option.votePercentage)%")
                        .monospacedDigit()
                        .accessibilityHidden(true)
                }
            }

            if presentation.resultsVisible {
                ProgressView(value: Double(option.votePercentage), total: 100)
                    .tint(optionColor(option, isSelected: isSelected, presentation: presentation))
                    .accessibilityHidden(true)
            }

            HStack(spacing: 8) {
                if presentation.resultsVisible {
                    Text(telegramPollVoteCountDescription(option.voterCount))
                }
                if option.isCorrect == true, presentation.resultsVisible {
                    Text("Correct answer")
                } else if presentation.isQuiz, option.isChosen, presentation.resultsVisible {
                    Text("Incorrect answer")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .contentShape(.rect)
        .padding(8)
        .background(
            optionColor(option, isSelected: isSelected, presentation: presentation).opacity(isSelected ? 0.14 : 0.04),
            in: RoundedRectangle(cornerRadius: 9),
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    optionColor(option, isSelected: isSelected, presentation: presentation).opacity(0.45),
                    lineWidth: isSelected ? 1.5 : 1,
                )
        }
    }

    private func optionColor(
        _ option: TelegramPollOptionPresentation,
        isSelected: Bool,
        presentation: TelegramPollPresentation,
    ) -> Color {
        if presentation.resultsVisible, option.isCorrect == true {
            return .green
        }
        if presentation.resultsVisible, presentation.isQuiz, option.isChosen {
            return .red
        }
        return isSelected ? .accentColor : .secondary
    }

    private func optionAccessibilityValue(
        _ option: TelegramPollOptionPresentation,
        isSelected: Bool,
        presentation: TelegramPollPresentation,
    ) -> String {
        var parts = [isSelected ? "Checked" : "Not checked"]
        if presentation.resultsVisible {
            parts.append("\(option.votePercentage) percent")
            parts.append(telegramPollVoteCountDescription(option.voterCount))
        }
        if presentation.resultsVisible, option.isCorrect == true {
            parts.append("Correct answer")
        } else if presentation.resultsVisible, presentation.isQuiz, option.isChosen {
            parts.append("Incorrect answer")
        }
        return parts.joined(separator: ", ")
    }

    private func submit(_ optionPositions: [Int]) {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        errorIsFocused = false
        Task {
            do {
                try await TelegramMessageActions.setPollAnswer(
                    service: service,
                    message: message,
                    optionPositions: optionPositions,
                )
                selection = Set(optionPositions)
            } catch {
                errorMessage = "Vote failed: \(telegramErrorDescription(error))"
                await Task.yield()
                errorIsFocused = true
            }
            isSubmitting = false
        }
    }
}

// MARK: - TelegramPollVoterPresentation

private struct TelegramPollVoterPresentation: Identifiable {
    let voterId: MessageSender
    var name: String
    var optionPositions: Set<Int>
    var voteDate: Int

    var id: String {
        switch voterId {
        case .messageSenderUser(let user): "user-\(user.userId)"
        case .messageSenderChat(let chat): "chat-\(chat.chatId)"
        }
    }
}

// MARK: - TelegramPollVotersView

private struct TelegramPollVotersView: View {
    // MARK: Internal

    let content: MessagePoll
    let message: Message
    let service: any TelegramService

    var body: some View {
        let presentation = TelegramPollPresentation(content)
        NavigationStack {
            List {
                Section("Poll") {
                    Text(presentation.question)
                }

                Section("Voters") {
                    ForEach(sortedVoters) { voter in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(voter.name)
                                .font(.headline)
                            Text("Voted for: \(answerDescription(for: voter, presentation: presentation))")
                            Text(telegramMessageDateDescription(voter.voteDate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    if voters.isEmpty, !isLoading, errorMessage == nil {
                        Text("No votes yet")
                            .foregroundStyle(.secondary)
                    }

                    if isLoading {
                        ProgressView("Loading votes")
                    }

                    if !remainingOptionPositions.isEmpty, !isLoading {
                        Button("Load More Votes") { loadMore() }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityFocused($errorIsFocused)
                    }
                }
            }
            .navigationTitle("Poll Votes")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 430, minHeight: 500)
        #endif
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadPages(for: Set(presentation.options.filter { $0.voterCount > 0 }.map(\.position)))
        }
    }

    // MARK: Private

    @AccessibilityFocusState private var errorIsFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var voters = [MessageSender: TelegramPollVoterPresentation]()
    @State private var voterNames = [MessageSender: String]()
    @State private var offsets = [Int: Int]()
    @State private var remainingOptionPositions = Set<Int>()
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    private var sortedVoters: [TelegramPollVoterPresentation] {
        voters.values.sorted {
            if $0.voteDate != $1.voteDate {
                return $0.voteDate > $1.voteDate
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func answerDescription(
        for voter: TelegramPollVoterPresentation,
        presentation: TelegramPollPresentation,
    ) -> String {
        presentation.options
            .filter { voter.optionPositions.contains($0.position) }
            .map(\.text)
            .joined(separator: ", ")
    }

    private func loadMore() {
        guard !isLoading else { return }
        Task { await loadPages(for: remainingOptionPositions) }
    }

    private func loadPages(for optionPositions: Set<Int>) async {
        guard !optionPositions.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        errorIsFocused = false
        var stillRemaining = remainingOptionPositions
        do {
            for position in optionPositions.sorted() {
                try Task.checkCancellation()
                let offset = offsets[position, default: 0]
                let page = try await service.getPollVoters(
                    chatId: message.chatId,
                    limit: 50,
                    messageId: message.id,
                    offset: offset,
                    optionId: position,
                )
                for voter in page.voters {
                    let name: String
                    if let existingName = voterNames[voter.voterId] {
                        name = existingName
                    } else {
                        name = await TelegramSenderName.displayName(service: service, senderId: voter.voterId)
                            ?? "Unknown voter"
                        voterNames[voter.voterId] = name
                    }

                    if var existing = voters[voter.voterId] {
                        existing.optionPositions.insert(position)
                        existing.voteDate = max(existing.voteDate, voter.date)
                        voters[voter.voterId] = existing
                    } else {
                        voters[voter.voterId] = TelegramPollVoterPresentation(
                            voterId: voter.voterId,
                            name: name,
                            optionPositions: [position],
                            voteDate: voter.date,
                        )
                    }
                }

                let newOffset = offset + page.voters.count
                offsets[position] = newOffset
                if !page.voters.isEmpty, newOffset < page.totalCount {
                    stillRemaining.insert(position)
                } else {
                    stillRemaining.remove(position)
                }
            }
            remainingOptionPositions = stillRemaining
        } catch is CancellationError {
            // The sheet was dismissed while loading.
        } catch {
            errorMessage = telegramErrorDescription(error)
            await Task.yield()
            errorIsFocused = true
        }
        isLoading = false
    }
}
