// TelegramLocation.swift

import TDLibKit

// MARK: - TelegramLocationPresentation

/// Normalizes TDLib's three separate "point on a map" message contents - a one-shot location, a
/// live location that updates while `expiresIn` counts down, and a venue - into one shape, so the
/// message bubble and its "Open in Maps" action don't need to special-case each of them.
struct TelegramLocationPresentation: Equatable {
    // MARK: Lifecycle

    init?(_ content: MessageContent) {
        switch content {
        case .messageLocation(let content):
            self.location = content.location
            self.title = "Location"
            self.subtitle = nil
            self.isLive = false
            self.isVenue = false
        case .messageLiveLocation(let content):
            self.location = content.location.location
            self.title = "Live Location"
            self.subtitle = nil
            self.isLive = true
            self.isVenue = false
        case .messageVenue(let content):
            self.location = content.venue.location
            self.title = content.venue.title
            self.subtitle = content.venue.address.isEmpty ? nil : content.venue.address
            self.isLive = false
            self.isVenue = true
        default:
            return nil
        }
    }

    // MARK: Internal

    let location: Location
    let title: String
    let subtitle: String?
    let isLive: Bool
    let isVenue: Bool

    var coordinateText: String {
        String(format: "%.5f, %.5f", location.latitude, location.longitude)
    }

    /// Always leads with the word "Location" (except the live case, which already says as much)
    /// so VoiceOver users can tell this is a location message rather than plain text - a venue's
    /// name/address alone would otherwise read just like an ordinary message. Raw coordinates
    /// aren't useful spoken aloud, so a plain location has nothing to add after the word.
    var contentDescription: String {
        if isLive {
            "Live Location"
        } else if isVenue {
            if let subtitle {
                "Location: \(title), \(subtitle)"
            } else {
                "Location: \(title)"
            }
        } else {
            "Location"
        }
    }
}
