import SwiftUI

struct QuickSwitcherView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var results: [WorkspaceSession] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ordered = model.sessions.sorted { $0.lastActivatedAt > $1.lastActivatedAt }
        guard !value.isEmpty else { return ordered }
        return ordered.filter { $0.searchableText.contains(value) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Jump to a session…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                Text("esc")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(16)

            Divider()

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(Array(results.prefix(12).enumerated()), id: \.element.id) { index, session in
                        Button {
                            model.select(session.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                StatusDot(
                                    activity: session.activity,
                                    isWorking: model.workingSessionIDs.contains(session.id)
                                )
                                Image(systemName: session.symbolName)
                                    .foregroundStyle(Color(nsColor: session.iconColor))
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title)
                                        .foregroundStyle(.primary)
                                    Text("\(session.agent.displayName) · \(session.workingDirectory)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if index < 9 {
                                    Text("⌘\(index + 1)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(7)
            }
            .frame(maxHeight: 430)
        }
        .frame(width: 560)
        .onAppear { searchFocused = true }
    }
}
