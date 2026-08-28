// ConferenceParticipantVolumeView.swift

import SwiftUI

// MARK: - ConferenceParticipantVolumeView

struct ConferenceParticipantVolumeView: View {
    // MARK: Lifecycle

    init(
        participantName: String,
        initialVolumeLevel: Int,
        setVolume: @escaping (Int, Bool) -> Void,
    ) {
        self.participantName = participantName
        self.setVolume = setVolume
        let boundedVolumeLevel = min(20000, max(0, initialVolumeLevel))
        _volumeLevel = State(initialValue: Double(boundedVolumeLevel))
        _lastSynchronizedVolumeLevel = State(initialValue: boundedVolumeLevel)
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Slider(
                        value: $volumeLevel,
                        in: 0...20000,
                        step: 100,
                        onEditingChanged: volumeEditingChanged,
                    )
                    .accessibilityLabel("Volume")
                    .accessibilityValue("\(volumePercentage) percent")

                    Text("\(volumePercentage)%")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityHidden(true)
                }
            }
            .navigationTitle(participantName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .onChange(of: volumeLevel) { _, newValue in
                setVolume(Int(newValue), false)
            }
            .onDisappear(perform: synchronizeVolumeIfNeeded)
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var lastSynchronizedVolumeLevel: Int
    @State private var volumeLevel: Double

    private let participantName: String
    private let setVolume: (Int, Bool) -> Void

    private var volumePercentage: Int {
        Int((volumeLevel / 100).rounded())
    }

    private func volumeEditingChanged(_ isEditing: Bool) {
        guard !isEditing else { return }
        synchronizeVolumeIfNeeded()
    }

    private func synchronizeVolumeIfNeeded() {
        let updatedVolumeLevel = Int(volumeLevel)
        guard lastSynchronizedVolumeLevel != updatedVolumeLevel else { return }
        lastSynchronizedVolumeLevel = updatedVolumeLevel
        setVolume(updatedVolumeLevel, true)
    }
}
