// VideoChatManagementView.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - VideoChatManagementView

struct VideoChatManagementView: View {
    // MARK: Lifecycle

    init(
        chatId: Int64,
        service: any TelegramService,
        initialCall: GroupCall,
        onUpdated: @escaping (GroupCall?) -> Void,
    ) {
        self.chatId = chatId
        self.service = service
        self.initialCall = initialCall
        self.onUpdated = onUpdated
        self._call = State(initialValue: initialCall)
        self._isRecording = State(initialValue: initialCall.recordDuration > 0 || initialCall.isVideoRecorded)
        self._title = State(initialValue: initialCall.title)
    }

    // MARK: Internal

    let chatId: Int64
    let service: any TelegramService
    let initialCall: GroupCall
    let onUpdated: (GroupCall?) -> Void

    var body: some View {
        Form {
            Section("Title") {
                TextField("Voice Chat", text: $title)
                Button("Save Title") { Task { await saveTitle() } }
                    .disabled(title == call.title || isWorking)
            }

            if call.canToggleMuteNewParticipants || call.canToggleAreMessagesAllowed {
                Section("Permissions") {
                    if call.canToggleMuteNewParticipants {
                        Toggle("Only Admins Can Unmute New Participants", isOn: muteNewParticipantsBinding)
                            .disabled(isWorking)
                    }
                    if call.canToggleAreMessagesAllowed {
                        Toggle("Allow Messages", isOn: messagesAllowedBinding)
                            .disabled(isWorking)
                    }
                }
            }

            Section("Invite Links") {
                if let listenerLink {
                    ShareLink(item: listenerLink) {
                        Label("Share Listener Link", systemImage: "ear")
                    }
                }
                if let speakerLink {
                    ShareLink(item: speakerLink) {
                        Label("Share Speaker Link", systemImage: "mic")
                    }
                }
                Button("Refresh Invite Links", systemImage: "arrow.clockwise") {
                    Task { await loadLinks() }
                }
                Button("Revoke Invite Links", systemImage: "link.badge.minus", role: .destructive) {
                    Task { await revokeLinks() }
                }
            }

            Section("Recording") {
                if isRecording {
                    Label("Recording in progress", systemImage: "record.circle.fill")
                        .foregroundStyle(.red)
                    Button("Stop Recording", role: .destructive) {
                        Task { await stopRecording() }
                    }
                } else {
                    Button("Start Audio Recording", systemImage: "waveform") {
                        Task { await startRecording(video: false) }
                    }
                    Button("Start Video Recording", systemImage: "video") {
                        Task { await startRecording(video: true) }
                    }
                }
            }

            if call.isRtmpStream {
                Section {
                    NavigationLink("Stream Key and URL") {
                        VideoChatRtmpView(
                            chatId: chatId,
                            service: service,
                            createsStream: false,
                            onCreated: nil,
                        )
                    }
                }
            }

            Section {
                Button("End Voice Chat", role: .destructive) {
                    showsEndConfirmation = true
                }
            }
        }
        .navigationTitle("Voice Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadLinks() }
        .onReceive(service.updatePublisher) { update in
            guard case .updateGroupCall(let value) = update, value.groupCall.id == call.id else { return }
            apply(value.groupCall)
        }
        .alert("End Voice Chat for Everyone?", isPresented: $showsEndConfirmation) {
            Button("End for Everyone", role: .destructive) {
                Task { await endCall() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The voice chat ends for every participant.")
        }
        .alert("Voice Chat Error", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var call: GroupCall
    @State private var errorMessage: String?
    @State private var isRecording: Bool
    @State private var isWorking = false
    @State private var listenerLink: URL?
    @State private var showsEndConfirmation = false
    @State private var speakerLink: URL?
    @State private var title: String

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

    private var muteNewParticipantsBinding: Binding<Bool> {
        Binding(
            get: { call.muteNewParticipants },
            set: { value in Task { await setMuteNewParticipants(value) } },
        )
    }

    private var messagesAllowedBinding: Binding<Bool> {
        Binding(
            get: { call.areMessagesAllowed },
            set: { value in Task { await setMessagesAllowed(value) } },
        )
    }

    @MainActor private func perform(_ operation: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await operation()
            try await apply(service.getGroupCall(groupCallId: call.id))
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func saveTitle() async {
        await perform {
            _ = try await service.setVideoChatTitle(groupCallId: call.id, title: title)
        }
    }

    @MainActor private func setMuteNewParticipants(_ value: Bool) async {
        await perform {
            _ = try await service.toggleVideoChatMuteNewParticipants(
                groupCallId: call.id,
                muteNewParticipants: value,
            )
        }
    }

    @MainActor private func setMessagesAllowed(_ value: Bool) async {
        await perform {
            _ = try await service.toggleGroupCallAreMessagesAllowed(
                areMessagesAllowed: value,
                groupCallId: call.id,
            )
        }
    }

    @MainActor private func loadLinks() async {
        do {
            let groupCallId = call.id
            async let listener = service.getVideoChatInviteLink(canSelfUnmute: false, groupCallId: groupCallId)
            async let speaker = service.getVideoChatInviteLink(canSelfUnmute: true, groupCallId: groupCallId)
            let (listenerValue, speakerValue) = try await (listener, speaker)
            listenerLink = URL(string: listenerValue.url)
            speakerLink = URL(string: speakerValue.url)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func revokeLinks() async {
        do {
            _ = try await service.revokeGroupCallInviteLink(groupCallId: call.id)
            await loadLinks()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func startRecording(video: Bool) async {
        await perform {
            _ = try await service.startGroupCallRecording(
                groupCallId: call.id,
                recordVideo: video,
                title: title,
                usePortraitOrientation: false,
            )
        }
        if errorMessage == nil {
            isRecording = true
        }
    }

    @MainActor private func stopRecording() async {
        await perform {
            _ = try await service.endGroupCallRecording(groupCallId: call.id)
        }
        if errorMessage == nil {
            isRecording = false
        }
    }

    @MainActor private func endCall() async {
        do {
            _ = try await service.endGroupCall(groupCallId: call.id)
            onUpdated(nil)
            dismiss()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func apply(_ updated: GroupCall) {
        // Follow the server title only while the field hasn't been edited away from what we last
        // knew - don't overwrite a title the user is in the middle of typing.
        if title == call.title {
            title = updated.title
        }
        call = updated
        isRecording = updated.recordDuration > 0 || updated.isVideoRecorded
        onUpdated(updated)
    }
}
