import SwiftUI
import StasksCore

struct PanelHeaderView: View {
    @Bindable var model: PanelModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Text("Stasks").font(.system(size: 15, weight: .bold)).tracking(-0.2)
                .onTapGesture(count: 2) { model.onResetHeight() }
                .help(L("panel.help.resetHeight"))
            Text("\(model.store.activeCount)")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Theme.chip(scheme), in: Capsule())
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                withAnimation(.spring(duration: 0.25)) { model.prefs.order = model.prefs.order == .lifo ? .fifo : .lifo }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: model.prefs.order == .lifo ? "arrow.down.to.line" : "arrow.up.to.line")
                        .font(.system(size: 9, weight: .bold))
                    Text(model.prefs.order == .lifo ? "LIFO" : "FIFO")
                        .font(.system(size: 10, weight: .semibold)).tracking(0.3)
                }
                .padding(.horizontal, 8)
            }
            .buttonStyle(HeaderButtonStyle(chip: true))
            .help(model.prefs.order == .lifo ? L("panel.help.lifo") : L("panel.help.fifo"))

            Button { model.togglePin() } label: { Image(systemName: model.prefs.pinned ? "pin.fill" : "pin") }
                .buttonStyle(HeaderButtonStyle(active: model.prefs.pinned))
                .help(L("panel.help.pin"))
        }
        .padding(.horizontal, 6)
    }
}

/// Quiet header control. Ghost at rest, `Theme.chip` on hover, and a soft accent tint when `active`,
/// so the header reads like the count chip next to it instead of a row of primary buttons.
/// `chip` keeps the chip background at rest, for controls that show a mode rather than trigger an action.
struct HeaderButtonStyle: ButtonStyle {
    var active = false
    var chip = false
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .frame(minWidth: 24, minHeight: 24)
            .background(background(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .foregroundStyle(active ? Theme.accent : Color.secondary)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private func background(pressed: Bool) -> Color {
        if active { return Theme.accent.opacity(pressed ? 0.28 : hovering ? 0.24 : 0.18) }
        if pressed { return scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.10) }
        if hovering || chip { return Theme.chip(scheme) }
        return .clear
    }
}
