// TelegramNotificationSoundPicker.swift

import AVFoundation
import SwiftUI
@preconcurrency import TDLibKit
import UniformTypeIdentifiers

// MARK: - TelegramNotificationSoundPickerView

/// A push destination (works identically on both platforms - see the comment on
/// `TelegramNotificationScopeDetailView` for why nested `NavigationLink`s are safe here even on
/// macOS). Mirrors Telegram-iOS's own sound picker: "Default"/"Off", then the account's saved
/// cloud sounds (synced across devices via TDLib), with upload and delete.
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
                    soundRow(title: sound.title, soundId: sound.id, duration: sound.duration)
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

    private func soundRow(title: String, soundId: TdInt64, duration: Int? = nil) -> some View {
        Button {
            select(soundId: soundId)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let duration {
                        Text(durationString(duration))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if soundId == selectedSoundId {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(soundId == selectedSoundId ? [.isSelected] : [])
    }

    private func durationString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
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
