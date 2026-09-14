// ChatBannerLayoutTests.swift

@testable import BetterTG
import SwiftUI
import Testing
import UIKit

@MainActor struct ChatBannerLayoutTests {
    // MARK: Internal

    @Test(arguments: [DynamicTypeSize.large, .accessibility3])
    func `translation label uses text height instead of consuming half the screen`(typeSize: DynamicTypeSize) throws {
        let host = UIHostingController(rootView:
            VStack(spacing: 0) {
                StableTranslationBannerLabel(text: "Translate from Romanian?")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(maxHeight: .infinity)
            }.dynamicTypeSize(typeSize))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        let label = try #require(findLabel(in: host.view))
        let expected = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height
        #expect(label.bounds.width > 0)
        #expect(expected > 0)
        #expect(abs(label.bounds.height - expected) < 2)
        #expect(label.bounds.height < 200)
    }

    // MARK: Private

    private func findLabel(in view: UIView) -> UILabel? {
        if let label = view as? UILabel {
            return label
        }
        return view.subviews.lazy.compactMap { findLabel(in: $0) }.first
    }
}
