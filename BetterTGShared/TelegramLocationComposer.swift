// TelegramLocationComposer.swift

import CoreLocation
import MapKit
import SwiftUI
import TDLibKit

// MARK: - TelegramLocationDraft

struct TelegramLocationDraft: Equatable {
    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracy: Double = 0
    var address: String?

    var isValid: Bool {
        (try? inputMessageContent()) != nil
    }

    func inputMessageContent() throws -> InputMessageContent {
        guard let latitude, let longitude else {
            throw TelegramLocationDraftValidationError.locationRequired
        }
        return .inputMessageLocation(.init(location: Location(
            horizontalAccuracy: horizontalAccuracy,
            latitude: latitude,
            longitude: longitude,
        )))
    }
}

// MARK: - TelegramLocationDraftValidationError

enum TelegramLocationDraftValidationError: Swift.Error, Equatable, LocalizedError {
    case locationRequired

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .locationRequired:
            "Couldn't determine your location yet."
        }
    }
}

// MARK: - TelegramLocationSending

enum TelegramLocationSending {
    @discardableResult static func send(
        draft: TelegramLocationDraft,
        service: any TelegramService,
        chatId: Int64,
        replyToMessageId: Int64?,
    ) async throws -> Message {
        let content = try draft.inputMessageContent()
        let messages = try await TelegramMessageSending.send(
            service: service,
            chatId: chatId,
            contents: [content],
            replyTo: TelegramMessageSending.replyTo(messageId: replyToMessageId),
            onAccepted: { messages in
                service.mergeMessages(chatId: chatId, messages: messages)
            },
        )
        guard let message = messages.first else {
            throw TelegramLocationSendingError.noMessageReturned
        }
        return message
    }
}

// MARK: - TelegramLocationSendingError

private enum TelegramLocationSendingError: Swift.Error, LocalizedError {
    case noMessageReturned

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .noMessageReturned:
            "Telegram accepted the location but didn't return the sent message."
        }
    }
}

// MARK: - TelegramLocationComposerView

struct TelegramLocationComposerView: View {
    // MARK: Lifecycle

    init(
        requestCurrentLocation: @escaping () async throws -> CLLocation,
        onOpenSettings: (() -> Void)? = nil,
        onSend: @escaping (TelegramLocationDraft) async throws -> Void,
    ) {
        self.requestCurrentLocation = requestCurrentLocation
        self.onOpenSettings = onOpenSettings
        self.onSend = onSend
    }

    // MARK: Internal

    let requestCurrentLocation: () async throws -> CLLocation
    let onOpenSettings: (() -> Void)?
    let onSend: (TelegramLocationDraft) async throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                statusSection

                if isSending {
                    Section { ProgressView("Sending location") }
                }
                if let feedbackMessage {
                    Section {
                        Text(feedbackMessage)
                            .foregroundStyle(.red)
                            .accessibilityFocused($feedbackIsFocused)
                    }
                }
            }
            .navigationTitle("Send Location")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                            .disabled(isSending)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { send() }
                            .disabled(isSending || !draft.isValid)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 320)
        #endif
        .task {
            guard !hasRequestedLocation else { return }
            hasRequestedLocation = true
            await fetchCurrentLocation()
        }
    }

    // MARK: Private

    @AccessibilityFocusState private var feedbackIsFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TelegramLocationDraft()
    @State private var isFetchingLocation = false
    @State private var isSending = false
    @State private var hasRequestedLocation = false
    @State private var fetchErrorMessage: String?
    @State private var fetchErrorIsPermissionDenied = false
    @State private var feedbackMessage: String?

    private var coordinateText: String {
        guard let latitude = draft.latitude, let longitude = draft.longitude else { return "" }
        return String(format: "%.5f, %.5f", latitude, longitude)
    }

    @ViewBuilder private var statusSection: some View {
        if isFetchingLocation {
            Section { ProgressView("Finding your location…") }
        } else if let fetchErrorMessage {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(fetchErrorMessage)
                    if fetchErrorIsPermissionDenied, let onOpenSettings {
                        Button("Open Settings", action: onOpenSettings)
                    } else {
                        Button("Try Again") { Task { await fetchCurrentLocation() } }
                    }
                }
            }
        } else if draft.latitude != nil, draft.longitude != nil {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Current Location")
                        Text(draft.address ?? coordinateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Best-effort only - a missing/failed reverse geocode just falls back to raw coordinates
    /// (`coordinateText`), never blocks sending.
    private static func reverseGeocodedAddress(for location: CLLocation) async -> String? {
        // `MKReverseGeocodingRequest` (the current MapKit API - `CLGeocoder` is deprecated as of
        // iOS/macOS 26) needs iOS/macOS 26 itself, which is above this app's macOS 15 deployment
        // target (its iOS target is already 26) - macOS 15-25 falls back to `CLGeocoder`.
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
            return await withCheckedContinuation { continuation in
                request.getMapItems { items, _ in
                    continuation.resume(returning: items?.first?.name)
                }
            }
        } else {
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
            return [placemark.name, placemark.locality, placemark.country]
                .compactMap(\.self)
                .joined(separator: ", ")
        }
    }

    @MainActor private func fetchCurrentLocation() async {
        isFetchingLocation = true
        fetchErrorMessage = nil
        defer { isFetchingLocation = false }
        do {
            let location = try await requestCurrentLocation()
            draft.latitude = location.coordinate.latitude
            draft.longitude = location.coordinate.longitude
            draft.horizontalAccuracy = max(location.horizontalAccuracy, 0)
            draft.address = await Self.reverseGeocodedAddress(for: location)
        } catch {
            fetchErrorIsPermissionDenied = (error as? LocationAccessError) == .accessDenied
            fetchErrorMessage = telegramErrorDescription(error)
        }
    }

    private func send() {
        feedbackMessage = nil
        feedbackIsFocused = false
        isSending = true
        Task {
            do {
                try await onSend(draft)
                dismiss()
            } catch {
                isSending = false
                feedbackMessage = telegramErrorDescription(error)
                feedbackIsFocused = true
            }
        }
    }
}
