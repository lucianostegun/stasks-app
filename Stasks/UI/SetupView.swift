import SwiftUI
import StasksCore

struct SetupView: View {
    @Bindable var model: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("setup.title")).font(.title2.weight(.semibold))
                    Text(L("setup.subtitle")).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 18)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.items) { item in
                        row(item)
                        if item.id != model.items.last?.id { Divider().padding(.leading, 56) }
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack(spacing: 10) {
                Button(L("setup.recheck")) { model.refresh() }
                if let msg = model.message { Text(msg).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                Button(L("setup.openSettings")) { model.onOpenSettings(.general) }
                Button(L("setup.done")) { model.finish() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 520)
        .onAppear { model.refresh(); model.startAutoRefresh() }
        .onDisappear { model.stopAutoRefresh() }
    }

    private func row(_ item: SetupModel.Item) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol(item.state))
                .font(.system(size: 18))
                .foregroundStyle(color(item.state))
                .frame(width: 24)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title).font(.body.weight(.medium))
                    Text(item.required ? L("setup.required") : L("setup.optional"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Text(item.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let action = item.action {
                Button(action.label, action: action.run).controlSize(.small)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func symbol(_ s: SetupModel.State) -> String {
        switch s {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .off: return "circle.dashed"
        }
    }

    private func color(_ s: SetupModel.State) -> Color {
        switch s {
        case .ok: return .green
        case .warning: return .orange
        case .error: return .red
        case .off: return .secondary
        }
    }
}
