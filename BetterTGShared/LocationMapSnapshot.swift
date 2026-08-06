// LocationMapSnapshot.swift

import CoreLocation
@preconcurrency import MapKit

#if os(iOS)
import UIKit

public typealias PlatformMapImage = UIImage
#else
import AppKit

public typealias PlatformMapImage = NSImage
#endif

// MARK: - LocationMapSnapshot

/// Generates small static map thumbnails for `MessageLocation` bubbles, with an in-memory cache
/// so scrolling the same message repeatedly doesn't re-render tiles each time.
enum LocationMapSnapshot {
    // MARK: Internal

    static func image(
        latitude: Double,
        longitude: Double,
        size: CGSize,
        scale: CGFloat,
    ) async -> PlatformMapImage? {
        let key = cacheKey(latitude: latitude, longitude: longitude, size: size, scale: scale)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            latitudinalMeters: 600,
            longitudinalMeters: 600,
        )
        options.size = size
        #if os(iOS)
        options.scale = scale
        #endif
        options.showsBuildings = true

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else {
            return nil
        }
        let image = await MainActor.run { composited(pinOver: snapshot.image, size: size) }
        cache.setObject(image, forKey: key)
        return image
    }

    // MARK: Private

    private static let cache: NSCache<NSString, PlatformMapImage> = {
        let cache = NSCache<NSString, PlatformMapImage>()
        cache.countLimit = 40
        return cache
    }()

    private static func cacheKey(latitude: Double, longitude: Double, size: CGSize, scale: CGFloat) -> NSString {
        let roundedLatitude = (latitude * 10000).rounded() / 10000
        let roundedLongitude = (longitude * 10000).rounded() / 10000
        return "\(roundedLatitude),\(roundedLongitude),\(Int(size.width))x\(Int(size.height))@\(scale)" as NSString
    }

    @MainActor private static func composited(pinOver baseImage: PlatformMapImage, size: CGSize) -> PlatformMapImage {
        let pinSize: CGFloat = 30
        let pinRect = CGRect(
            x: size.width / 2 - pinSize / 2,
            y: size.height / 2 - pinSize,
            width: pinSize,
            height: pinSize,
        )

        #if os(iOS)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            baseImage.draw(in: CGRect(origin: .zero, size: size))
            UIImage(systemName: "mappin.circle.fill")?
                .withTintColor(.systemRed, renderingMode: .alwaysOriginal)
                .draw(in: pinRect)
        }
        #else
        let image = NSImage(size: size)
        image.lockFocus()
        baseImage.draw(in: CGRect(origin: .zero, size: size))
        if let pinImage = NSImage(systemSymbolName: "mappin.circle.fill", accessibilityDescription: nil) {
            let tinted = pinImage.withSymbolConfiguration(.init(paletteColors: [.systemRed])) ?? pinImage
            tinted.draw(in: pinRect)
        }
        image.unlockFocus()
        return image
        #endif
    }
}
