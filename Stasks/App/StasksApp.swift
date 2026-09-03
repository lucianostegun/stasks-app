import SwiftUI

@main
struct StasksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            Text("Settings placeholder")
                .frame(width: 420, height: 300)
        }
    }
}
