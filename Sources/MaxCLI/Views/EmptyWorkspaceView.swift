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
                Text(model.tr("empty.title"))
                    .font(.title2.weight(.semibold))
                Text(model.tr("empty.subtitle"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button {
                model.isShowingNewSession = true
            } label: {
                Label(model.tr("empty.createFirst"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 20) {
                Label(model.tr("empty.new"), systemImage: "keyboard")
                Label(model.tr("empty.switch"), systemImage: "arrow.left.arrow.right")
                Label(model.tr("empty.grid"), systemImage: "square.grid.2x2")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
