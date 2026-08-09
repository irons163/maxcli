import SwiftUI

struct TerminalPane: View {
    @EnvironmentObject private var model: AppModel
    let session: WorkspaceSession
    let compact: Bool

    private var isSelected: Bool { model.selectedSessionID == session.id }
    private var runtime: TerminalRuntime? { model.runtime(for: session.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            terminalContent
        }
        .background(Color(nsColor: NSColor(calibratedWhite: 0.055, alpha: 1)))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 0))
        .overlay {
            if compact {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            }
        }
        .shadow(color: .black.opacity(compact ? 0.18 : 0), radius: 8, y: 3)
    }

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(activity: session.activity)

            Image(systemName: session.agent.symbolName)
                .foregroundStyle(Color(nsColor: session.agent.color))

            Text(session.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            Text(session.directoryName)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)

            Spacer()

            if runtime?.isRunning == true {
                Button {
                    model.stop(session.id)
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.55))
                .help("Stop session")
            } else {
                Button {
                    model.restart(session.id)
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: compact ? 35 : 39)
        .background(Color.white.opacity(isSelected ? 0.07 : 0.035))
        .contentShape(Rectangle())
        .onTapGesture { model.select(session.id) }
    }

    @ViewBuilder
    private var terminalContent: some View {
        if let runtime {
            ZStack(alignment: .bottom) {
                TerminalRepresentable(runtime: runtime, isFocused: isSelected)
                    .id(ObjectIdentifier(runtime))

                if !runtime.isRunning {
                    exitedOverlay
                }
            }
        } else {
            stoppedPlaceholder
        }
    }

    private var stoppedPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: compact ? 25 : 34, weight: .light))
                .foregroundStyle(.white.opacity(0.25))
            Text("Session is not running")
                .foregroundStyle(.white.opacity(0.55))
            Button("Start \(session.agent.displayName)") {
                model.start(session.id)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var exitedOverlay: some View {
        HStack(spacing: 8) {
            Text(session.activity == .failed ? "Process failed" : "Process exited")
            Button("Restart") { model.restart(session.id) }
                .buttonStyle(.borderless)
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.74), in: Capsule())
        .padding(.bottom, 10)
    }
}
