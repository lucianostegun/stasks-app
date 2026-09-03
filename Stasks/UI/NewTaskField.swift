import SwiftUI

struct NewTaskField: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            TextField(L("panel.newTask.placeholder"), text: $text)
                .textFieldStyle(.plain).font(.system(size: 12.5))
                .focused(focus)
                .onSubmit { onSubmit() }
                .onExitCommand { text = ""; focus.wrappedValue = false }
            Text("⌘N").font(.system(size: 10)).padding(.horizontal, 5).padding(.vertical, 1)
                .background(Theme.chip(scheme), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.15))
                .background(Theme.rowHover(scheme).opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        )
    }
}
