// MacChatFolderPicker.swift

import SwiftUI

struct MacChatFolderPicker: View {
    @Bindable var model: MacSessionModel

    var body: some View {
        Picker(
            "Chat folder",
            selection: Binding(
                get: { model.selectedChatFolderId },
                set: { folderId in
                    guard let folder = model.availableChatFolders.first(where: { $0.id == folderId }) else { return }
                    model.selectChatFolder(folder)
                },
            ),
        ) {
            ForEach(model.availableChatFolders) { folder in
                Text(folder.title).tag(folder.id)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
