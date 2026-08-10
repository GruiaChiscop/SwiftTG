// TelegramEmojiCategoryBar.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramEmojiCategoryBar

struct TelegramEmojiCategoryBar: View {
    let categories: [EmojiCategory]
    let selectedCategory: EmojiCategory?
    let onSelect: (EmojiCategory?) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                ForEach(categories.indices, id: \.self) { index in
                    let category = categories[index]
                    let isSelected = selectedCategory == category
                    Button(
                        category.name,
                        systemImage: isSelected ? "checkmark.circle.fill" : "circle.grid.2x2",
                    ) {
                        onSelect(isSelected ? nil : category)
                    }
                    .buttonStyle(.bordered)
                    .tint(isSelected ? .accentColor : .secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}
