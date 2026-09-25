import AppKit
import SwiftUI

@main
struct EDLPreviewApp: App {
    var body: some Scene {
        Window("EDL Preview", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    private let extensionsSettings = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EDL Preview")
                .font(.title2.bold())
            Text("The Quick Look extension is installed. Select an .edl file in Finder and press Space to preview it.")
            Text("If previews don't appear, enable EDL Preview under System Settings → General → Login Items & Extensions → Quick Look.")
                .foregroundStyle(.secondary)
            if let extensionsSettings {
                Button("Open Extensions Settings…") {
                    NSWorkspace.shared.open(extensionsSettings)
                }
            }
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
