// ChatScrollLogView.swift

#if DEBUG
import SwiftUI

struct ChatScrollLogView: View {
    @State private var text = ChatScrollDiagnostics.shared.exportedText
    @State private var didCopy = false

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Chat Scroll Log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Copy") {
                    UIPasteboard.general.string = ChatScrollDiagnostics.shared.exportedText
                    didCopy = true
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Clear") {
                    ChatScrollDiagnostics.shared.clear()
                    text = ChatScrollDiagnostics.shared.exportedText
                }
            }
        }
        .task {
            // Refresh periodically while this screen is open, so a repro that just happened shows
            // up without needing to navigate back and forth.
            while !Task.isCancelled {
                text = ChatScrollDiagnostics.shared.exportedText
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .alert("Copied", isPresented: $didCopy) {
            Button("OK") {}
        }
    }
}
#endif
