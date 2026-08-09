import SwiftUI

struct EmptyWorkspaceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.tint.opacity(0.12))
                    .frame(width: 78, height: 78)
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.tint)
            }
            VStack(spacing: 6) {
                Text("Your AI command center")
                    .font(.title2.weight(.semibold))
                Text("Run Codex, Claude Code, Gemini and other CLIs side by side.\nEach session keeps its own terminal and working directory.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button {
                model.isShowingNewSession = true
            } label: {
                Label("Create First Session", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 20) {
                Label("⌘N New", systemImage: "keyboard")
                Label("⌘K Switch", systemImage: "arrow.left.arrow.right")
                Label("⌘⇧G Grid", systemImage: "square.grid.2x2")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
