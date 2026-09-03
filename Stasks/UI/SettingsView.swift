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
            general.tabItem { Label("Geral", systemImage: "gearshape") }
            claude.tabItem { Label("Claude", systemImage: "terminal") }
            slack.tabItem { Label("Slack", systemImage: "number") }
            anthropic.tabItem { Label("Anthropic", systemImage: "sparkles") }
        }
        .frame(width: 460, height: 320)
        .onAppear { model.refreshHookStatus() }
    }

    private var general: some View {
        Form {
            Picker("Ordem da pilha", selection: $prefs.order) {
                Text("LIFO (mais recente no topo)").tag(StackOrder.lifo)
                Text("FIFO (mais antiga no topo)").tag(StackOrder.fifo)
            }
            Stepper("Esconder concluídas após \(Int(prefs.hideDoneAfterHours))h", value: $prefs.hideDoneAfterHours, in: 1...72)
            Picker("Atalho global", selection: $prefs.hotKey) {
                ForEach(HotKeyChoice.allCases) { Text($0.label).tag($0) }
            }
            .onChange(of: prefs.hotKey) { _, new in model.onHotKeyChanged(new) }
            Toggle("Abrir no login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
        }.formStyle(.grouped)
    }

    private var claude: some View {
        Form {
            LabeledContent("Hooks do Claude Code") {
                switch model.hookStatus {
                case .installed: Label("Instalados", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .outdated: Label("Desatualizados", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case .missing: Label("Ausentes", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            Button(model.hookStatus == .installed ? "Reinstalar hooks" : "Instalar hooks") { model.installHooks() }
            if let msg = model.hookMessage { Text(msg).font(.caption).foregroundStyle(.secondary) }
            LabeledContent("Inbox") { Text(model.inboxPath).font(.caption).textSelection(.enabled) }
            Button("Abrir logs no Console") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"))
            }
        }.formStyle(.grouped)
    }

    private var slack: some View {
        Form {
            SecureField("User token (xoxp-…)", text: $model.slackToken)
            HStack {
                Button("Salvar") { model.saveSlackToken() }
                Button("Testar") { Task { await model.testSlack() } }.disabled(model.slackToken.isEmpty)
            }
            if let r = model.slackTestResult { Text(r).font(.caption).foregroundStyle(.secondary) }
            Slider(value: $prefs.pollInterval, in: 10...60, step: 5) { Text("Polling: \(Int(prefs.pollInterval))s") }
                .onChange(of: prefs.pollInterval) { _, new in model.onPollIntervalChanged(new) }
            Text("Scopes: reactions:read, channels:history, groups:history, im:history, mpim:history, channels:read, groups:read, users:read")
                .font(.caption2).foregroundStyle(.tertiary)
        }.formStyle(.grouped)
    }

    private var anthropic: some View {
        Form {
            Toggle("Gerar títulos com LLM", isOn: $prefs.llmEnabled)
            SecureField("API key (sk-ant-…)", text: $model.anthropicKey)
            HStack {
                Button("Salvar") { model.saveAnthropicKey() }
                Button("Testar") { Task { await model.testAnthropic() } }.disabled(model.anthropicKey.isEmpty)
            }
            if let r = model.anthropicTestResult { Text(r).font(.caption).foregroundStyle(.secondary) }
            Text("Modelo: \(AnthropicClient.model)").font(.caption2).foregroundStyle(.tertiary)
        }.formStyle(.grouped)
    }
}
