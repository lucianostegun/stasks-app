import SwiftUI

@main
struct StasksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            if let model = appDelegate.settingsModel { SettingsView(model: model) } else { Text("…") }
        }
    }
}
