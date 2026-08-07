// TelegramNotificationSoundPicker.swift

import AVFoundation
import SwiftUI
@preconcurrency import TDLibKit
import UniformTypeIdentifiers

// MARK: - TelegramNotificationSoundPickerView

/// The same List-based sound picker on both platforms - "Default"/"Off", then the account's saved
/// cloud sounds (synced across devices via TDLib), with upload and delete. iOS pushes to this
/// directly (works identically wherever it's pushed from - see the comment on
/// `TelegramNotificationScopeDetailView` for why nested `NavigationLink`s are safe here even on
/// macOS). macOS instead wraps it in a sheet (`TelegramNotificationSoundPickerSheet` below), the
/// same way `TelegramPrivacyView` and the notification scope screens present their own detail
/// content: a List/NavigationLink placed inside (or reachable through) a NavigationSplitView's
/// detail column on macOS auto-selects and auto-activates its first row as soon as it appears, and
/// a sheet's own NavigationStack sidesteps that entirely.
struct TelegramNotificationSoundPickerView: View {
    // MARK: Internal

    let service: any TelegramService
    let selectedSoundId: TdInt64
    let onSelect: (TdInt64) -> Void

    var body: some View {
        List {
            Section {
                soundRow(title: "Default", soundId: -1)
                soundRow(title: "Off", soundId: 0)
            }

            Section {
                ForEach(savedSounds) { sound in
                    soundRow(title: sound.title, soundId: sound.id)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                Task { await delete(sound) }
                            }
                        }
                }

                Button {
                    isImportingSound = true
                } label: {
                    Label("Upload Sound…", systemImage: "square.and.arrow.up")
                }
                .disabled(isUploading)
            } header: {
                Text("My Sounds")
            } footer: {
                Text("Uploaded sounds sync to your other Telegram devices, just like in the official app.")
            }
        }
        .navigationTitle("Sound")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                await load()
            }
            .fileImporter(isPresented: $isImportingSound, allowedContentTypes: [.mp3], onCompletion: handleImport)
            .overlay {
                if isLoading || isUploading {
                    ProgressView()
                }
            }
            .alert("Sound operation failed", isPresented: errorIsPresented) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    // MARK: Private

    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var isImportingSound = false
    @State private var isLoading = false
    @State private var isUploading = false
    @State private var player: AVAudioPlayer?
    @State private var savedSounds: [NotificationSound] = []

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            },
        )
    }

    private func soundRow(title: String, soundId: TdInt64) -> some View {
        Button {
            select(soundId: soundId)
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if soundId == selectedSoundId {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func select(soundId: TdInt64) {
        onSelect(soundId)
        playPreview(soundId: soundId)
    }

    private func playPreview(soundId: TdInt64) {
        guard soundId > 0, let sound = savedSounds.first(where: { $0.id == soundId }) else { return }
        Task {
            guard let file = try? await service.downloadFile(
                fileId: sound.sound.id,
                limit: 0,
                offset: 0,
                priority: 1,
                synchronous: true,
            ), file.local.isDownloadingCompleted, !file.local.path.isEmpty else { return }
            await MainActor.run {
                #if os(iOS)
                // Without `.mixWithOthers`, activating the session for this one-off preview takes
                // exclusive control of audio output and cuts off VoiceOver's own speech mid-word -
                // which then has to re-announce the screen, reading as a spurious "reload" with
                // focus reset to the top.
                try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
                try? AVAudioSession.sharedInstance().setActive(true, options: [])
                #endif
                player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: file.local.path))
                player?.play()
            }
        }
    }

    @MainActor private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            savedSounds = try await service.getSavedNotificationSounds().notificationSounds
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    private func handleImport(_ result: Result<URL, Swift.Error>) {
        guard case .success(let url) = result else { return }
        Task { await upload(url: url) }
    }

    @MainActor private func upload(url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        isUploading = true
        defer { isUploading = false }
        do {
            // TDLib reads the file itself, on its own schedule - it needs a plain path it still
            // owns after this function returns, not the caller's security-scoped one.
            let tempURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp3")
            try? FileManager.default.removeItem(at: tempURL)
            try FileManager.default.copyItem(at: url, to: tempURL)

            let uploaded = try await service.addSavedNotificationSound(
                sound: .inputFileLocal(InputFileLocal(path: tempURL.path)),
            )
            savedSounds.removeAll { $0.id == uploaded.id }
            savedSounds.insert(uploaded, at: 0)
            select(soundId: uploaded.id)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func delete(_ sound: NotificationSound) async {
        do {
            _ = try await service.removeSavedNotificationSound(notificationSoundId: sound.id)
            savedSounds.removeAll { $0.id == sound.id }
            if selectedSoundId == sound.id {
                onSelect(-1)
            }
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}

// MARK: - TelegramNotificationSoundPickerSheet

#if os(macOS)
/// macOS-only sheet wrapper around `TelegramNotificationSoundPickerView`, mirroring
/// `TelegramNotificationScopeDetailView`'s own sheet wrapper for the same reason.
struct TelegramNotificationSoundPickerSheet: View {
    // MARK: Internal

    let service: any TelegramService
    let selectedSoundId: TdInt64
    let onSelect: (TdInt64) -> Void

    var body: some View {
        NavigationStack {
            TelegramNotificationSoundPickerView(service: service, selectedSoundId: selectedSoundId, onSelect: onSelect)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .frame(minWidth: 380, minHeight: 420)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}
#endif
