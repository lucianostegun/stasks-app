import SwiftUI
import StasksCore

struct StackPanelView: View {
    @Bindable var model: PanelModel
    @Environment(\.colorScheme) private var scheme
    @State private var newTitle = ""
    @FocusState private var newFocused: Bool

    private var active: [TaskItem] { model.store.activeTasks(order: model.prefs.order) }
    private var completed: [TaskItem] { model.store.completedTasks(withinHours: model.prefs.hideDoneAfterHours) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeaderView(model: model) { newFocused = true }
                .padding(.bottom, 10)

            if let banner = model.errorBanner {
                Button(action: model.onOpenSettings) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 6, height: 6)
                        Text(banner).font(.system(size: 11)).lineLimit(1)
                        Spacer(); Text("Ajustes").font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.bottom, 8)
            }

            if model.prefs.order == .lifo { newField.padding(.bottom, 8) }

            ScrollView {
                LazyVStack(spacing: 2) {
                    if active.isEmpty {
                        Text("Nada em aberto").font(.system(size: 12)).foregroundStyle(.tertiary).padding(.vertical, 18)
                    }
                    ForEach(active) { task in row(task) }
                }
            }
            .frame(maxHeight: model.manualHeight == nil ? model.maxListHeight : .infinity)
            .scrollBounceBehavior(.basedOnSize)

            if model.prefs.order == .fifo { newField.padding(.top, 8) }

            if !completed.isEmpty {
                Divider().opacity(0.4).padding(.horizontal, 6).padding(.vertical, 8)
                Button {
                    withAnimation(.spring(duration: 0.25)) { model.prefs.completedCollapsed.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: model.prefs.completedCollapsed ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .bold))
                        Text("Concluídas").font(.system(size: 12, weight: .semibold))
                        Text("\(completed.count)").font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 7).padding(.vertical, 1).background(Theme.chip(scheme), in: Capsule())
                        Spacer()
                    }.foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4)
                }.buttonStyle(.plain)

                if !model.prefs.completedCollapsed {
                    LazyVStack(spacing: 2) { ForEach(completed) { task in row(task).opacity(0.8) } }
                        .frame(maxHeight: 220)
                }
            }
        }
        .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 10)
        .frame(width: Theme.panelWidth)
        .frame(height: model.manualHeight, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panelTint(scheme))
        // Circular corners here match the NSVisualEffectView mask exactly; a continuous curve would show a double edge.
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .circular).strokeBorder(Theme.panelBorder(scheme), lineWidth: 1))
        .animation(.spring(duration: 0.25), value: active.map(\.id))
        .animation(.spring(duration: 0.25), value: completed.map(\.id))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.onSizeChange($0) }
        .overlay(settingsShortcut)
    }

    /// Invisible button so ⌘, opens Settings while the panel is the key window.
    private var settingsShortcut: some View {
        Button("") { model.onOpenSettings() }
            .keyboardShortcut(",", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
    }

    private var newField: some View {
        NewTaskField(text: $newTitle, focus: $newFocused) {
            model.createManual(newTitle); newTitle = ""
        }
    }

    private func row(_ task: TaskItem) -> some View {
        TaskRowView(task: task, now: model.now,
                    onOpen: { model.open(task) },
                    onStatus: { model.setStatus(task, $0) },
                    onRename: { model.rename(task, to: $0) },
                    onRemove: { model.remove(task) })
            .transition(.asymmetric(insertion: .move(edge: model.prefs.order == .lifo ? .top : .bottom).combined(with: .opacity),
                                    removal: .opacity.combined(with: .scale(scale: 0.96))))
    }
}
