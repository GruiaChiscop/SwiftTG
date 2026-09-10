// ChatHistoryMeasuredRow.swift

import SwiftUI

// MARK: - ChatHistoryMeasuredRow

struct ChatHistoryMeasuredRow: View {
    let row: ChatHistoryRowView
    let reportHeight: ((CGFloat) -> Void)?

    var body: some View {
        row
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { geometry in
                ceil(geometry.size.height)
            } action: { height in
                guard height > 0 else { return }
                reportHeight?(height)
            }
    }
}
