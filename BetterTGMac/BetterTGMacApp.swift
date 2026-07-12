import SwiftUI
import TDLibKit

@main struct BetterTGMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 960, height: 700)
    }
}

private struct ContentView: View {
    var body: some View {
        ContentUnavailableView(
            "BetterTG for Mac",
            systemImage: "paperplane",
            description: Text("The macOS interface will be added incrementally."),
        )
    }
}
