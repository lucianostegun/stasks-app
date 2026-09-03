import Foundation
import Observation
import ServiceManagement
import StasksCore

@MainActor
@Observable
final class SettingsModel {
    let prefs: Preferences
    private let hookInstaller: HookInstaller
    private let slackTestFactory: (String) -> any SlackAPI
    private let anthropicTestFactory: (String) -> any AnthropicAPI

    var slackToken: String = KeychainStore.get(KeychainStore.slackToken) ?? ""
    var anthropicKey: String = KeychainStore.get(KeychainStore.anthropicKey) ?? ""
    var hookStatus: HookStatus = .missing
    var hookMessage: String?
    var slackTestResult: String?
    var anthropicTestResult: String?

    @ObservationIgnored var onCredentialsChanged: () -> Void = {}
    @ObservationIgnored var onHotKeyChanged: (HotKeyChoice) -> Void = { _ in }
    @ObservationIgnored var onPollIntervalChanged: (Double) -> Void = { _ in }

    init(prefs: Preferences, hookInstaller: HookInstaller,
         slackTestFactory: @escaping (String) -> any SlackAPI, anthropicTestFactory: @escaping (String) -> any AnthropicAPI) {
        self.prefs = prefs
        self.hookInstaller = hookInstaller
        self.slackTestFactory = slackTestFactory
        self.anthropicTestFactory = anthropicTestFactory
        refreshHookStatus()
    }

    var inboxPath: String { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Stasks/inbox.jsonl").path }

    func refreshHookStatus() {
        do { hookStatus = try hookInstaller.status(); hookMessage = nil }
        catch { hookStatus = .missing; hookMessage = error.localizedDescription }
    }

    func installHooks() {
        do {
            let backup = try hookInstaller.install()
            hookMessage = "Hooks instalados. Backup: \(backup.lastPathComponent)"
        } catch { hookMessage = "Falha: \(error.localizedDescription)" }
        refreshHookStatus()
    }

    func saveSlackToken() { KeychainStore.set(KeychainStore.slackToken, slackToken); onCredentialsChanged() }
    func saveAnthropicKey() { KeychainStore.set(KeychainStore.anthropicKey, anthropicKey); onCredentialsChanged() }

    func testSlack() async {
        slackTestResult = "Testando…"
        do {
            let auth = try await slackTestFactory(slackToken.trimmingCharacters(in: .whitespacesAndNewlines)).authTest()
            slackTestResult = "OK: \(auth.team) como @\(auth.user)"
        } catch { slackTestResult = "Falha: \(String(describing: error))" }
    }

    func testAnthropic() async {
        anthropicTestResult = "Testando…"
        do {
            let text = try await anthropicTestFactory(anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines))
                .complete(system: "Responda apenas OK.", user: "ping", maxTokens: 5)
            anthropicTestResult = "OK (\(text.trimmingCharacters(in: .whitespacesAndNewlines)))"
        } catch { anthropicTestResult = "Falha: \(String(describing: error))" }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() } catch { hookMessage = error.localizedDescription } }
    }
}
