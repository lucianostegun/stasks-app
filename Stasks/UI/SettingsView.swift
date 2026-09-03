import SwiftUI
import StasksCore

struct SettingsView: View {
    @Bindable var model: SettingsModel
    @Bindable var prefs: Preferences

    init(model: SettingsModel) {
        self.model = model
        self.prefs = model.prefs
    }

    var body: some View {
        TabView {
            general.tabItem { Label(L("settings.tab.general"), systemImage: "gearshape") }
            claude.tabItem { Label("Claude", systemImage: "terminal") }
            slack.tabItem { Label("Slack", systemImage: "number") }
            titles.tabItem { Label(L("settings.tab.titles"), systemImage: "sparkles") }
            sounds.tabItem { Label(L("settings.tab.sounds"), systemImage: "speaker.wave.2") }
        }
        .padding(.top, 12)
        .frame(width: 560, height: 440)
        .onAppear { model.refreshHookStatus() }
    }

    private var general: some View {
        Form {
            Picker(L("settings.language"), selection: $prefs.language) {
                ForEach(AppLanguage.selectable) { Text($0.nativeName).tag($0) }
            }
            Picker(L("settings.order"), selection: $prefs.order) {
                Text(L("settings.order.lifo")).tag(StackOrder.lifo)
                Text(L("settings.order.fifo")).tag(StackOrder.fifo)
            }
            Stepper(L("settings.hideDoneAfter", Int(prefs.hideDoneAfterHours)), value: $prefs.hideDoneAfterHours, in: 1...72)
            Picker(L("settings.hotKey"), selection: $prefs.hotKey) {
                ForEach(HotKeyChoice.allCases) { Text($0.label).tag($0) }
            }
            .onChange(of: prefs.hotKey) { _, new in model.onHotKeyChanged(new) }
            Toggle(L("settings.launchAtLogin"), isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
            if let msg = model.generalMessage { Text(msg).font(.caption).foregroundStyle(.secondary) }
        }.formStyle(.grouped)
    }

    private var claude: some View {
        Form {
            LabeledContent(L("settings.claude.hooks")) {
                switch model.hookStatus {
                case .installed: Label(L("settings.claude.hooks.installed"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .outdated: Label(L("settings.claude.hooks.outdated"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case .missing: Label(L("settings.claude.hooks.missing"), systemImage: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            Button(model.hookStatus == .installed ? L("settings.claude.reinstall") : L("settings.claude.install")) { model.installHooks() }
            if let msg = model.hookMessage { Text(msg).font(.caption).foregroundStyle(.secondary) }
            LabeledContent(L("settings.claude.inbox")) { Text(model.inboxPath).font(.caption).textSelection(.enabled) }
            Button(L("settings.claude.openLogs")) {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"))
            }
        }.formStyle(.grouped)
    }

    private var slack: some View {
        Form {
            SecureField(L("settings.slack.token"), text: $model.slackToken, prompt: Text("xoxp-…"))
            HStack {
                Button(L("common.save")) { model.saveSlackToken() }
                Button(L("common.test")) { Task { await model.testSlack() } }.disabled(model.slackToken.isEmpty)
            }
            if let r = model.slackTestResult { Text(r).font(.caption).foregroundStyle(.secondary) }
            Slider(value: $prefs.pollInterval, in: 10...60, step: 5) { Text(L("settings.slack.polling", Int(prefs.pollInterval))) }
                .onChange(of: prefs.pollInterval) { _, new in model.onPollIntervalChanged(new) }
            Text("Scopes: reactions:read, channels:history, groups:history, im:history, mpim:history, channels:read, groups:read, users:read")
                .font(.caption2).foregroundStyle(.tertiary)
        }.formStyle(.grouped).textFieldStyle(.roundedBorder)
    }

    private var sounds: some View {
        Form {
            Toggle(L("settings.sounds.enabled"), isOn: $prefs.soundEnabled)
            Picker(L("settings.sounds.sound"), selection: $prefs.soundName) {
                ForEach(AttentionSound.availableNames, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: prefs.soundName) { _, _ in model.previewSound() }
            Slider(value: $prefs.soundVolume, in: 0...1, step: 0.05) {
                Text(L("settings.sounds.volume", Int((prefs.soundVolume * 100).rounded())))
            } onEditingChanged: { editing in if !editing { model.previewSound() } }
            Button(L("settings.sounds.preview")) { model.previewSound() }
            Text(L("settings.sounds.hint")).font(.caption2).foregroundStyle(.tertiary)
        }
        .formStyle(.grouped)
    }

    private var titles: some View {
        Form {
            Toggle(L("settings.titles.enabled"), isOn: $prefs.llmEnabled)
            Picker(L("settings.titles.provider"), selection: $prefs.titleProvider) {
                ForEach(TitleProvider.allCases) { Text($0.label).tag($0) }
            }
            .onChange(of: prefs.titleProvider) { _, _ in model.titleTestResult = nil }

            switch prefs.titleProvider {
            case .anthropic:
                SecureField(L("settings.titles.apiKey"), text: $model.anthropicKey, prompt: Text("sk-ant-…"))
                HStack {
                    Button(L("common.save")) { model.saveAnthropicKey() }
                    Button(L("common.test")) { Task { await model.testTitles() } }
                }
                Text(L("settings.titles.model.fixed", AnthropicClient.model)).font(.caption2).foregroundStyle(.tertiary)
            case .openAI:
                TextField(L("settings.titles.baseURL"), text: $prefs.openAIBaseURL, prompt: Text(OpenAICompatibleClient.defaultBaseURL))
                TextField(L("settings.titles.model"), text: $prefs.openAIModel, prompt: Text(OpenAICompatibleClient.defaultModel))
                SecureField(L("settings.titles.apiKey"), text: $model.openAIKey, prompt: Text("sk-…"))
                HStack {
                    Button(L("common.save")) { model.saveOpenAIKey() }
                    Button(L("common.test")) { Task { await model.testTitles() } }
                }
                Text(L("settings.titles.hint.openAI")).font(.caption2).foregroundStyle(.tertiary)
            case .claudeCode:
                TextField(L("settings.titles.model"), text: $prefs.claudeCodeModel, prompt: Text(ClaudeCodeClient.defaultModel))
                TextField(L("settings.titles.claudePath"), text: $prefs.claudeCodePath, prompt: Text(L("settings.titles.claudePath.auto")))
                LabeledContent(L("settings.titles.claudePath.detected")) {
                    Text(model.detectedClaudePath ?? L("settings.titles.claudeNotFound"))
                        .font(.caption).foregroundStyle(model.detectedClaudePath == nil ? .red : .secondary).textSelection(.enabled)
                }
                Button(L("common.test")) { Task { await model.testTitles() } }
                Text(L("settings.titles.hint.claudeCode")).font(.caption2).foregroundStyle(.tertiary)
            }
            if let r = model.titleTestResult { Text(r).font(.caption).foregroundStyle(.secondary) }
        }.formStyle(.grouped).textFieldStyle(.roundedBorder)
    }
}
