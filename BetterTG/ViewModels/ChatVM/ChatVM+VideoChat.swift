// ChatVM+VideoChat.swift

import Combine
import Foundation
@preconcurrency import TDLibKit

extension ChatVM {
    var hasActiveVideoChat: Bool { videoChat.groupCallId != 0 }

    /// Seeds `videoChat` from the chat snapshot and keeps it (and `videoChatCall`) live.
    func startVideoChatObservation() {
        videoChat = customChat.chat.videoChat
        let chatId = customChat.chat.id
        service.updatePublisher
            .filter { update in
                switch update {
                case .updateChatVideoChat(let value): value.chatId == chatId
                case .updateGroupCall: true
                default: false
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                Task { @MainActor in self?.applyVideoChatUpdate(update) }
            }
            .store(in: &cancellables)
        refreshVideoChat()
    }

    func refreshVideoChat() {
        videoChatRefreshTask?.cancel()
        let groupCallId = videoChat.groupCallId
        videoChatRefreshTask = Task { [weak self] in
            await self?.loadVideoChatCall(groupCallId: groupCallId)
        }
    }

    /// Identities the current user may join this chat's video chat as (self, plus any channel they
    /// post as). More than one means the caller should offer a "join as" choice.
    func videoChatJoinIdentities() async -> [MessageSender] {
        await (try? service.getVideoChatAvailableParticipants(chatId: customChat.chat.id))?.senders ?? []
    }

    @MainActor func loadVideoChatCall(groupCallId: Int) async {
        guard groupCallId != 0 else {
            videoChatCall = nil
            return
        }
        let call = try? await service.getGroupCall(groupCallId: groupCallId)
        guard !Task.isCancelled, groupCallId == videoChat.groupCallId else { return }
        videoChatCall = call
    }

    /// Reflects a video chat just created for this chat before `updateChatVideoChat` lands.
    @MainActor func applyCreatedVideoChat(_ call: GroupCall) {
        videoChat = VideoChat(
            defaultParticipantId: videoChat.defaultParticipantId,
            groupCallId: call.id,
            hasParticipants: call.participantCount > 0,
        )
        videoChatCall = call
    }

    @MainActor private func applyVideoChatUpdate(_ update: Update) {
        switch update {
        case .updateChatVideoChat(let value):
            videoChat = value.videoChat
            refreshVideoChat()
        case .updateGroupCall(let value) where value.groupCall.id == videoChat.groupCallId:
            videoChatCall = value.groupCall
        default:
            break
        }
    }
}
