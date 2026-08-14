import SwiftUI

struct StatusDot: View {
    let activity: SessionActivity
    var isWorking = false
    @EnvironmentObject private var model: AppModel
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

    @State private var spinning = false

    private var spinner: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }

    var body: some View {
        ZStack {
            if isWorking, !reduceMotion {
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 2.5)
                spinner
            } else if isWorking {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            } else {
                Circle()
                    .fill(color)
            }
        }
        .frame(width: 11, height: 11)
        .shadow(color: isWorking ? color.opacity(0.6) : .clear, radius: 3)
        .accessibilityLabel(model.tr(activity.labelKey))
    }
}
