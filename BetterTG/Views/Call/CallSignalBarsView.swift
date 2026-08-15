// CallSignalBarsView.swift

import SwiftUI

// MARK: - CallSignalBarsView

struct CallSignalBarsView: View {
    let bars: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .frame(width: 3, height: CGFloat(index + 1) * 3)
                    .foregroundStyle(index < bars ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            }
        }
        .frame(minWidth: 18, minHeight: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Call signal")
        .accessibilityValue("\(bars) of 4 bars")
    }
}
