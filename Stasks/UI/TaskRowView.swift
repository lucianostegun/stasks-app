import SwiftUI
import StasksCore

struct TaskRowView: View {
    let task: TaskItem
    let now: Date
    let onOpen: () -> Void
    let onStatus: (TaskStatus) -> Void
    let onRename: (String) -> Void
    let onRemove: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var isDone: Bool { task.status == .done }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 10) {
                if editing {
                    TextField("Título", text: $draft)
                        .textFieldStyle(.plain).font(.system(size: 13, weight: .semibold))
                        .focused($focused)
                        .onSubmit { onRename(draft); editing = false }
                        .onExitCommand { editing = false }
                } else {
                    Text(task.title)
                        .font(.system(size: 13, weight: .semibold)).tracking(-0.1)
                        .lineLimit(1).truncationMode(.tail)
                        .strikethrough(isDone)
                        .opacity(isDone ? 0.5 : 1)
                        .opacity(task.isProvisionalTitle ? 0.75 : 1)
                }
                Spacer(minLength: 0)
                Text(Theme.sourceGlyph(task.source.kind))
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(Theme.sourceColor(task.source.kind), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .opacity(isDone ? 0.6 : 1)
            }
            HStack(spacing: 10) {
                Text(task.subtitle ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                Text(RelativeTime.label(from: isDone ? (task.completedAt ?? task.createdAt) : task.createdAt, to: now))
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 9).padding(.leading, 14).padding(.trailing, 12)
        .background(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.statusColor(task.status))
                .frame(width: 3)
                .shadow(color: Theme.statusColor(task.status).opacity(0.6), radius: 4)
                .padding(.vertical, 10).padding(.leading, 4)
                .animation(.spring(duration: 0.2), value: task.status)
        }
        .background(hovering ? Theme.rowHover(scheme) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { startEditing() }
        .onTapGesture(count: 1) { if !editing { onOpen() } }
        .contextMenu {
            ForEach(TaskStatus.allCases, id: \.self) { s in
                Button { onStatus(s) } label: {
                    Label(label(for: s), systemImage: task.status == s ? "checkmark.circle.fill" : "circle")
                }
            }
            Divider()
            if task.source.kind != .manual { Button("Abrir origem") { onOpen() } }
            Button("Editar título") { startEditing() }
            Button("Remover", role: .destructive) { onRemove() }
        }
    }

    private func startEditing() { draft = task.title; editing = true; focused = true }

    private func label(for s: TaskStatus) -> String {
        switch s { case .open: return "Open"; case .inProgress: return "In progress"; case .done: return "Done" }
    }
}
