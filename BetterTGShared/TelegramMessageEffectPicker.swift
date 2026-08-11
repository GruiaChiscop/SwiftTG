// TelegramMessageEffectPicker.swift

import Combine
import SwiftUI
@preconcurrency import TDLibKit

struct TelegramMessageEffectPicker: View {
    // MARK: Internal

    let service: any TelegramService
    let onSelect: (TdInt64) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading Effects")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if effects.isEmpty {
                    ContentUnavailableView(
                        "No Message Effects",
                        systemImage: "sparkles",
                        description: Text("Telegram did not provide any effects for this account."),
                    )
                } else {
                    List(effects) { effect in
                        Button {
                            dismiss()
                            onSelect(effect.id)
                        } label: {
                            HStack {
                                Text(effect.emoji)
                                    .font(.title2)
                                Text(effect.isPremium ? "\(effect.emoji) Effect, Premium" : "\(effect.emoji) Effect")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Message Effect")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 360)
        .onReceive(service.availableMessageEffectsPublisher) { update in
            guard let update else {
                isLoading = false
                return
            }
            loadEffects(update.reactionEffectIds + update.stickerEffectIds)
        }
        .onDisappear { loadingTask?.cancel() }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var effects = [MessageEffect]()
    @State private var isLoading = true
    @State private var loadingTask: Task<Void, Never>?

    private func loadEffects(_ effectIds: [TdInt64]) {
        loadingTask?.cancel()
        loadingTask = Task {
            let loaded = await withTaskGroup(of: MessageEffect?.self) { group in
                for effectId in effectIds {
                    group.addTask {
                        try? await service.getMessageEffect(effectId: effectId)
                    }
                }
                var effectsById = [TdInt64: MessageEffect]()
                for await effect in group {
                    if let effect {
                        effectsById[effect.id] = effect
                    }
                }
                return effectIds.compactMap { effectsById[$0] }
            }
            guard !Task.isCancelled else { return }
            effects = loaded
            isLoading = false
        }
    }
}
