// TelegramPollTests.swift

@testable import BetterTG
import TDLibKit
import Testing

struct TelegramPollTests {
    // MARK: Internal

    @Test func `presentation preserves Telegram option order and quiz results`() {
        let presentation = TelegramPollPresentation(messagePoll(
            allowsRevoting: true,
            correctOptionIds: [1],
            optionOrder: [1, 0],
            options: [
                pollOption(text: "First", percentage: 25, voters: 1),
                pollOption(text: "Second", percentage: 75, voters: 3, isChosen: true),
            ],
        ))

        #expect(presentation.options.map(\.position) == [1, 0])
        #expect(presentation.options.map(\.text) == ["Second", "First"])
        #expect(presentation.options[0].isCorrect == true)
        #expect(presentation.chosenOptionPositions == [1])
        #expect(presentation.resultsVisible)
        #expect(presentation.canVote)
        #expect(!presentation.canGetVoters)
        #expect(presentation.contentDescription == "Quiz: Question. Options: Second; First. 4 votes")
    }

    @Test func `single and multiple answer selections follow poll rules`() {
        #expect(telegramPollSelection(afterToggling: 2, in: [1], allowsMultipleAnswers: false) == [2])
        #expect(telegramPollSelection(afterToggling: 2, in: [1], allowsMultipleAnswers: true) == [1, 2])
        #expect(telegramPollSelection(afterToggling: 1, in: [1, 2], allowsMultipleAnswers: true) == [2])
    }

    @Test func `vote descriptions are explicit`() {
        #expect(telegramPollVoteCountDescription(1) == "1 vote")
        #expect(telegramPollVoteCountDescription(2) == "2 votes")
        #expect(telegramPollVoteRestrictionDescription(.pollVoteRestrictionReasonClosed) == "Voting is closed")
        #expect(telegramPollVoteRestrictionDescription(
            .pollVoteRestrictionReasonMembershipRequired(.init(chatId: 5)),
        ) == "You must be a member of the chat for at least one day to vote")
    }

    @Test func `poll draft requires a question and two nonempty options`() {
        var draft = TelegramPollDraft()
        #expect(!draft.isValid)
        #expect(throws: TelegramPollDraftValidationError.questionRequired) {
            try draft.inputMessageContent()
        }

        draft.question = "Question"
        draft.options[0].text = "Only answer"
        #expect(!draft.isValid)
        #expect(throws: TelegramPollDraftValidationError.twoOptionsRequired) {
            try draft.inputMessageContent()
        }
    }

    @Test func `poll draft validates Telegram text limits`() {
        var draft = TelegramPollDraft()
        draft.question = String(repeating: "Q", count: TelegramPollDraft.maximumQuestionLength + 1)
        draft.options[0].text = "First"
        draft.options[1].text = "Second"
        #expect(throws: TelegramPollDraftValidationError.questionTooLong) {
            try draft.inputMessageContent()
        }

        draft.question = "Question"
        draft.options[1].text = String(repeating: "A", count: TelegramPollDraft.maximumOptionLength + 1)
        #expect(throws: TelegramPollDraftValidationError.optionTooLong(index: 2)) {
            try draft.inputMessageContent()
        }
    }

    @Test func `TDLib errors retain their useful server message`() {
        #expect(telegramErrorDescription(TDLibKit.Error(code: 1, message: "Polls are unavailable")) ==
            "Polls are unavailable")
        #expect(telegramErrorDescription(TDLibKit.Error(code: 406, message: "Internal detail")) ==
            "Telegram couldn't complete this action.")
    }

    @Test func `regular poll preserves sending settings`() throws {
        var draft = TelegramPollDraft()
        draft.question = "Question"
        draft.options[0].text = "First"
        draft.options[1].text = "Second"
        draft.allowsMultipleAnswers = true
        draft.allowsRevoting = true
        draft.shuffleOptions = true
        draft.isAnonymous = false
        #expect(draft.isValid)

        guard case .inputMessagePoll(let poll) = try draft.inputMessageContent() else {
            Issue.record("Expected poll content")
            return
        }
        #expect(poll.question.text == "Question")
        #expect(poll.options.map(\.text.text) == ["First", "Second"])
        #expect(poll.allowsMultipleAnswers)
        #expect(poll.allowsRevoting)
        #expect(poll.shuffleOptions)
        #expect(!poll.isAnonymous)
        guard case .inputPollTypeRegular = poll.type else {
            Issue.record("Expected a regular poll")
            return
        }
    }

    @Test func `quiz maps the selected answer after blank options are removed`() throws {
        let blank = TelegramPollDraftOption(text: "   ")
        let correct = TelegramPollDraftOption(text: "Correct")
        var draft = TelegramPollDraft()
        draft.kind = .quiz
        draft.question = "Question"
        draft.options = [blank, correct, TelegramPollDraftOption(text: "Incorrect")]
        draft.correctOptionId = correct.id
        draft.explanation = "Because"
        draft.allowsMultipleAnswers = true
        draft.allowsRevoting = true

        guard case .inputMessagePoll(let poll) = try draft.inputMessageContent() else {
            Issue.record("Expected poll content")
            return
        }
        #expect(poll.options.map(\.text.text) == ["Correct", "Incorrect"])
        #expect(!poll.allowsMultipleAnswers)
        #expect(!poll.allowsRevoting)
        guard case .inputPollTypeQuiz(let quiz) = poll.type else {
            Issue.record("Expected a quiz")
            return
        }
        #expect(quiz.correctOptionIds == [0])
        #expect(quiz.explanation.text == "Because")
    }

    // MARK: Private

    private func messagePoll(
        allowsRevoting: Bool,
        correctOptionIds: [Int],
        optionOrder: [Int],
        options: [PollOption],
    ) -> MessagePoll {
        MessagePoll(
            canAddOption: false,
            description: FormattedText(entities: [], text: "Description"),
            media: nil,
            poll: Poll(
                allowsMultipleAnswers: false,
                allowsRevoting: allowsRevoting,
                canGetVoters: false,
                canSeeResults: true,
                closeDate: 0,
                countryCodes: [],
                id: TdInt64(10),
                isAnonymous: true,
                isClosed: false,
                membersOnly: false,
                openPeriod: 0,
                optionOrder: optionOrder,
                options: options,
                question: FormattedText(entities: [], text: "Question"),
                recentVoterIds: [],
                totalVoterCount: options.reduce(0) { $0 + $1.voterCount },
                type: .pollTypeQuiz(.init(
                    correctOptionIds: correctOptionIds,
                    explanation: FormattedText(entities: [], text: "Why"),
                    explanationMedia: nil,
                )),
                voteRestrictionReason: nil,
            ),
        )
    }

    private func pollOption(
        text: String,
        percentage: Int,
        voters: Int,
        isChosen: Bool = false,
    ) -> PollOption {
        PollOption(
            additionDate: 0,
            author: nil,
            id: text,
            isBeingChosen: false,
            isChosen: isChosen,
            media: nil,
            recentVoterIds: [],
            text: FormattedText(entities: [], text: text),
            votePercentage: percentage,
            voterCount: voters,
        )
    }
}
