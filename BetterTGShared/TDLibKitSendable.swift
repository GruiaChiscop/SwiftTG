// TDLibKitSendable.swift

// swiftformat:disable markTypes
@preconcurrency import TDLibKit

// TDLibKit doesn't mark its generated types `Sendable`, so every value of theirs that crosses an
// isolation boundary (an actor-isolated method returning one, a closure capturing one) gets
// flagged under strict concurrency checking. In practice they're safe to send: every one of
// TDLibKit's ~1800 generated model files is a plain `struct`/`enum` built entirely from `let`
// stored properties (`Codable, Equatable, Hashable, Identifiable` value types decoded straight
// from TDLib's JSON) - there isn't a single class-based model in the whole generated surface, so
// there's no shared mutable state or reference identity for two copies to race over. `@unchecked`
// is required here only because the compiler can't synthesize `Sendable` for a type it doesn't
// own, not because these types need any actual runtime check the way `Media`/`MessageComposer`
// do elsewhere in this codebase.
//
// Only the types actually observed crossing isolation boundaries in this codebase are listed
// here - add to this list as strict-concurrency checking surfaces more, rather than trying to
// cover TDLibKit's full surface area up front.

// MARK: - Retroactive Sendable conformances

extension Message: @retroactive @unchecked Sendable {}
extension User: @retroactive @unchecked Sendable {}
extension Chat: @retroactive @unchecked Sendable {}
extension ChatList: @retroactive @unchecked Sendable {}
extension ChatFolderInfo: @retroactive @unchecked Sendable {}
extension ChatFolder: @retroactive @unchecked Sendable {}
extension ChatPosition: @retroactive @unchecked Sendable {}
extension ChatType: @retroactive @unchecked Sendable {}
extension DraftMessage: @retroactive @unchecked Sendable {}
extension MessageSender: @retroactive @unchecked Sendable {}
extension MessageContent: @retroactive @unchecked Sendable {}
extension MessageSchedulingState: @retroactive @unchecked Sendable {}
extension MessageReplyTo: @retroactive @unchecked Sendable {}
extension MessageOrigin: @retroactive @unchecked Sendable {}
extension InputMessageContent: @retroactive @unchecked Sendable {}
extension InputMessageReplyTo: @retroactive @unchecked Sendable {}
extension AvailableReaction: @retroactive @unchecked Sendable {}
extension ChatAction: @retroactive @unchecked Sendable {}
extension Session: @retroactive @unchecked Sendable {}
extension StickerSetInfo: @retroactive @unchecked Sendable {}
extension Sticker: @retroactive @unchecked Sendable {}
extension FormattedText: @retroactive @unchecked Sendable {}
extension LinkPreviewOptions: @retroactive @unchecked Sendable {}
extension ChatNotificationSettings: @retroactive @unchecked Sendable {}
extension Supergroup: @retroactive @unchecked Sendable {}
extension BasicGroup: @retroactive @unchecked Sendable {}
extension UserTypeBot: @retroactive @unchecked Sendable {}
extension PollOption: @retroactive @unchecked Sendable {}
extension FileType: @retroactive @unchecked Sendable {}
extension ReactionType: @retroactive @unchecked Sendable {}
extension File: @retroactive @unchecked Sendable {}
extension MessageProperties: @retroactive @unchecked Sendable {}
