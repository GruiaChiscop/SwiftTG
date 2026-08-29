// CallDetailView.swift

import SwiftUI
import TDLibKit

// MARK: - CallDetailView

/// The `i`-button screen for a Recent Calls row: peer header, quick actions, and every call in the
/// grouped run with its full date, type and duration.
struct CallDetailView: View {
    // MARK: Internal

    let title: String
    let userId: Int64
    let photo: File?
    let minithumbnail: Minithumbnail?
    let entries: [TelegramCallHistoryEntry]
    let onCallBack: (_ isVideo: Bool) -> Void
    let onMessage: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ProfileImageView(
                            photo: photo,
                            minithumbnail: minithumbnail,
                            title: title,
                            userId: userId,
                        )
                        .frame(width: 60, height: 60)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .font(.title3.weight(.semibold))
                            Text(entries.count == 1 ? "1 call" : "\(entries.count) calls")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                Section {
                    Button("Call", systemImage: "phone") { onCallBack(false) }
                    Button("Video Call", systemImage: "video") { onCallBack(true) }
                    Button("Message", systemImage: "message") { onMessage() }
                }

                Section("History") {
                    ForEach(entries) { entry in
                        HStack(spacing: 12) {
                            Image(systemName: iconName(for: entry))
                                .foregroundStyle(entry.isMissed ? .red : .secondary)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.isVideo ? "\(entry.shortStatus) · Video" : entry.shortStatus)
                                Text(telegramMessageDateDescription(entry.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if entry.duration > 1 {
                                Text(telegramCallDurationClock(entry.duration))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityLabel(for: entry))
                    }
                }
            }
            .navigationTitle("Call Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private func iconName(for entry: TelegramCallHistoryEntry) -> String {
        if entry.isMissed {
            return "arrow.down.left"
        }
        return entry.isOutgoing ? "arrow.up.right" : "arrow.down.left"
    }

    private func accessibilityLabel(for entry: TelegramCallHistoryEntry) -> String {
        var parts = [entry.spokenType, telegramMessageDateDescription(entry.date)]
        if entry.duration > 1 {
            parts.append(telegramSpokenDuration(entry.duration))
        }
        return parts.joined(separator: ", ")
    }
}
