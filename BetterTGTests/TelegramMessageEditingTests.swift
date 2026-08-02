// TelegramMessageEditingTests.swift

@testable import BetterTG
import TDLibKit
import Testing

struct TelegramMessageEditingTests {
    // MARK: Internal

    @Test func `text edit errors propagate to the caller`() async {
        let content = MessageContent.messageText(.init(
            linkPreview: nil,
            linkPreviewOptions: nil,
            text: FormattedText(entities: [], text: "Original"),
        ))

        do {
            _ = try await TelegramMessageEditing.performEdit(
                messageContent: content,
                editText: { throw ExpectedFailure.rejected },
                editCaption: { throw ExpectedFailure.rejected },
            )
            Issue.record("Expected the edit error to propagate")
        } catch let error as ExpectedFailure {
            #expect(error == .rejected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func `unsupported content does not invoke an edit request`() async throws {
        let edited = try await TelegramMessageEditing.performEdit(
            messageContent: .messageUnsupported,
            editText: { throw ExpectedFailure.rejected },
            editCaption: { throw ExpectedFailure.rejected },
        )

        #expect(edited == nil)
    }

    // MARK: Private

    private enum ExpectedFailure: Swift.Error, Equatable {
        case rejected
    }
}
