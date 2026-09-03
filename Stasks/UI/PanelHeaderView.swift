import SwiftUI
import StasksCore

struct PanelHeaderView: View {
    @Bindable var model: PanelModel
    @Environment(\.colorScheme) private var scheme
    var onNewTask: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Stasks").font(.system(size: 15, weight: .bold)).tracking(-0.2)
            Text("\(model.store.activeCount)")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Theme.chip(scheme), in: Capsule())
                .foregroundStyle(.secondary)
            Spacer()
            Button(model.prefs.order == .lifo ? "LIFO" : "FIFO") {
                withAnimation(.spring(duration: 0.25)) { model.prefs.order = model.prefs.order == .lifo ? .fifo : .lifo }
            }
            .buttonStyle(HeaderButtonStyle(active: true))
            .help(model.prefs.order == .lifo ? "Mais recente no topo" : "Mais antiga no topo")

            Button { model.togglePin() } label: { Image(systemName: model.prefs.pinned ? "pin.fill" : "pin") }
                .buttonStyle(HeaderButtonStyle(active: model.prefs.pinned))
                .help("Sempre visível")

            Button(action: onNewTask) { Image(systemName: "plus") }
                .buttonStyle(HeaderButtonStyle(active: false))
                .keyboardShortcut("n", modifiers: .command)
                .help("Nova tarefa (⌘N)")
        }
        .padding(.horizontal, 6)
    }
}

struct HeaderButtonStyle: ButtonStyle {
    var active: Bool
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .frame(minWidth: 26, minHeight: 26)
            .padding(.horizontal, 4)
            .background(active ? Theme.accent : Theme.chip(scheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .foregroundStyle(active ? Color.white : Color.primary.opacity(0.85))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
