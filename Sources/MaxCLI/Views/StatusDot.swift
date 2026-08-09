import SwiftUI

struct StatusDot: View {
    let activity: SessionActivity

    private var color: Color {
        switch activity {
        case .launching: .yellow
        case .running: .green
        case .attention: .orange
        case .stopped: .secondary
        case .failed: .red
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: activity == .running ? color.opacity(0.6) : .clear, radius: 3)
            .accessibilityLabel(activity.label)
    }
}
