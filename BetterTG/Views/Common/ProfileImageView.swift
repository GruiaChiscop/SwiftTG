// ProfileImageView.swift

import SwiftUI
import TDLibKit

// MARK: - ProfileImageView

struct ProfileImageView: View {
    let photo: File?
    let minithumbnail: Minithumbnail?
    let title: String
    let userId: Int64
    var fontSize: CGFloat = 20
    var isSavedMessages = false

    var body: some View {
        ZStack {
            if isSavedMessages {
                SavedMessagesIconView(fontSize: fontSize)
            } else if let photo {
                AsyncTdImage(id: photo.id, maxPixelSize: 256) { image, _ in
                    image
                        .resizable()
                        .scaledToFit()
                        .contentShape(.contextMenuPreview, Circle())
                        .contextMenu {
                            Button {
                                guard let uiImage = UIImage(contentsOfFile: photo.local.path) else { return }
                                UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                            } label: {
                                Label("Save", systemImage: "square.and.arrow.down")
                            }
                        } preview: {
                            image
                                .resizable()
                                .scaledToFit()
                        }
                } placeholder: {
                    if let image = Image(data: minithumbnail?.data) {
                        image
                            .resizable()
                            .scaledToFit()
                    } else {
                        PlaceholderView(title: title, id: userId, fontSize: fontSize)
                    }
                }
            } else {
                PlaceholderView(title: title, id: userId, fontSize: fontSize)
            }
        }
        .clipShape(.circle)
    }
}

// MARK: - SavedMessagesIconView

struct SavedMessagesIconView: View {
    var fontSize: CGFloat = 20

    var body: some View {
        Image(systemName: "bookmark.fill")
            .font(.system(size: fontSize * 0.9))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.accentColor.gradient)
    }
}

// MARK: - PlaceholderView

struct PlaceholderView: View {
    let title: String
    let id: Int64
    let fontSize: CGFloat
    
    var body: some View {
        Text(String(title.prefix(1).capitalized))
            .font(.system(size: fontSize, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(telegramAvatarId: id).gradient)
    }
}
