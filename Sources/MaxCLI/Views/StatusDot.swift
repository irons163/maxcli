import SwiftUI

struct StatusDot: View {
    let activity: SessionActivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        ZStack {
            if activity == .running, !reduceMotion {
                Circle()
                    .fill(color.opacity(0.3))
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let progress = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1)
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(progress * 360))
                }
            } else {
                Circle()
                    .fill(color)
            }
        }
        .frame(width: 9, height: 9)
        .shadow(color: activity == .running ? color.opacity(0.6) : .clear, radius: 3)
        .accessibilityLabel(activity.label)
    }
}
