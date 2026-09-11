import Foundation
import Security
import Observation
import ServiceManagement
import StasksCore

@MainActor
@Observable
final class SettingsModel {
    let prefs: Preferences
    private let hookInstaller: HookInstaller
    private let slackTestFactory: (String) -> any SlackAPI
    private let titleClientFactory: (Preferences) -> (any LLMClient)?

    var slackToken: String = KeychainStore.get(KeychainStore.slackToken) ?? ""
    var anthropicKey: String = KeychainStore.get(KeychainStore.anthropicKey) ?? ""
    var openAIKey: String = KeychainStore.get(KeychainStore.openAIKey) ?? ""
    var selectedTab: SettingsTab = .general
    var hookStatus: HookStatus = .missing
    var hookMessage: String?
    var generalMessage: String?
    var slackTestResult: String?
    var titleTestResult: String?

    @ObservationIgnored var onCredentialsChanged: () -> Void = {}
    @ObservationIgnored var onHotKeyChanged: (HotKeyChoice) -> Void = { _ in }
    @ObservationIgnored var onPollIntervalChanged: (Double) -> Void = { _ in }
    @ObservationIgnored var onHookStatusChanged: (HookStatus) -> Void = { _ in }
    @ObservationIgnored private let previewPlayer = AttentionSound()

    init(prefs: Preferences, hookInstaller: HookInstaller,
         slackTestFactory: @escaping (String) -> any SlackAPI, titleClientFactory: @escaping (Preferences) -> (any LLMClient)?) {
        self.prefs = prefs
        self.hookInstaller = hookInstaller
        self.slackTestFactory = slackTestFactory
        self.titleClientFactory = titleClientFactory
        refreshHookStatus()
    }

    var inboxPath: String { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Stasks/inbox.jsonl").path }

    func refreshHookStatus() {
        do { hookStatus = try hookInstaller.status(); hookMessage = nil }
        catch { hookStatus = .missing; hookMessage = error.localizedDescription }
        onHookStatusChanged(hookStatus)
    }

    func installHooks() {
        guard !hookInstaller.scriptPath.isEmpty else {
            hookMessage = L("settings.claude.scriptMissing")
            return
        }
        do {
            let backup = try hookInstaller.install()
            hookMessage = L("settings.claude.hooksInstalled", backup.lastPathComponent)
        } catch { hookMessage = L("common.failure", error.localizedDescription) }
        refreshHookStatus()
    }

    func saveSlackToken() {
        slackTestResult = Self.saveMessage(KeychainStore.set(KeychainStore.slackToken, slackToken))
        onCredentialsChanged()
    }

    func saveAnthropicKey() {
        titleTestResult = Self.saveMessage(KeychainStore.set(KeychainStore.anthropicKey, anthropicKey))
        onCredentialsChanged()
    }

    func saveOpenAIKey() {
        titleTestResult = Self.saveMessage(KeychainStore.set(KeychainStore.openAIKey, openAIKey))
        onCredentialsChanged()
    }

    /// Where `claude` will actually run from, for display next to the path field.
    var detectedClaudePath: String? { TitleClientFactory.resolvedClaudePath(prefs) }

    private static func saveMessage(_ status: OSStatus) -> String {
        status == errSecSuccess ? L("settings.keychain.saved") : L("settings.keychain.failed", Int(status))
    }

    func testSlack() async {
        slackTestResult = L("common.testing")
        do {
            let auth = try await slackTestFactory(slackToken.trimmingCharacters(in: .whitespacesAndNewlines)).authTest()
            slackTestResult = L("settings.slack.ok", auth.team, auth.user)
        } catch { slackTestResult = L("common.failure", String(describing: error)) }
    }

    /// Tests the provider currently selected, using saved credentials (unsaved edits in the key fields are not used).
    func testTitles() async {
        guard let client = titleClientFactory(prefs) else { titleTestResult = L("settings.titles.notConfigured"); return }
        titleTestResult = L("common.testing")
        do {
            let text = try await client.complete(system: "Reply with OK only.", user: "ping", maxTokens: 5)
            titleTestResult = "OK (\(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)))"
        } catch { titleTestResult = L("common.failure", String(describing: error)) }
    }

    func previewSound() { previewPlayer.play(name: prefs.soundName, volume: prefs.soundVolume) }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() } catch { generalMessage = error.localizedDescription } }
    }
}
