import SwiftUI
import UniformTypeIdentifiers

struct TerminalPane: View {
    @EnvironmentObject private var model: AppModel
    let session: WorkspaceSession
    let compact: Bool
    var onRequestClose: () -> Void = {}
    var headerDragID: String? = nil
    var onHeaderDragStart: (() -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil
    @State private var isDropTargeted = false

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
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            performDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: compact ? 10 : 0)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onDoubleClick?()
            }
        )
    }

    private func performDrop(_ providers: [NSItemProvider]) -> Bool {
        guard model.runtime(for: session.id)?.isRunning == true else { return false }
        Task {
            var paths: [String] = []
            for provider in providers {
                if let path = await droppedPath(for: provider) {
                    paths.append(path)
                }
            }
            let text = CommandBuilder.pastedPaths(paths)
            guard !text.isEmpty else { return }
            model.runtime(for: session.id)?.send(text: text)
        }
        return true
    }

    private func droppedPath(for provider: NSItemProvider) async -> String? {
        if provider.canLoadObject(ofClass: URL.self) {
            let url: URL? = await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: URL.self) { object, _ in
                    continuation.resume(returning: object as? URL)
                }
            }
            return url?.path
        }
        guard let data = await imageData(from: provider) else { return nil }
        return writeTemporaryImage(data: data)
    }

    private func imageData(from provider: NSItemProvider) async -> Data? {
        guard let type = provider.registeredTypeIdentifiers
            .first(where: { UTType($0)?.isSubtype(of: .image) ?? false })
        else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func writeTemporaryImage(data: Data) -> String? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaxCLIDrops", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("dropped-\(UUID().uuidString).png")
        do {
            try png.write(to: file)
            return file.path
        } catch {
            return nil
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(
                activity: session.activity,
                isWorking: model.workingSessionIDs.contains(session.id)
            )

            Image(systemName: session.symbolName)
                .foregroundStyle(Color(nsColor: session.iconColor))

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
                .help(model.tr("help.stop"))
            } else {
                Button {
                    model.restart(session.id)
                } label: {
                    Label(model.tr("pane.start"), systemImage: "play.fill")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.green)
            }

            Button {
                onRequestClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.45))
            .help(model.tr("help.closeSession"))
            .onHover { hovering in
                NSCursor.pointingHand.push()
                if !hovering { NSCursor.pop() }
            }
        }
        .padding(.horizontal, 11)
        .frame(height: compact ? 35 : 39)
        .background(Color.white.opacity(isSelected ? 0.07 : 0.035))
        .contentShape(Rectangle())
        .onTapGesture { model.select(session.id) }
        .modifier(DragSource(id: headerDragID, onStart: onHeaderDragStart))
    }

    private struct DragSource: ViewModifier {
        let id: String?
        var onStart: (() -> Void)? = nil

        @ViewBuilder
        func body(content: Content) -> some View {
            if let id {
                content.onDrag {
                    onStart?()
                    return NSItemProvider(object: id as NSString)
                }
            } else {
                content
            }
        }
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
            Text(model.tr("pane.notRunning"))
                .foregroundStyle(.white.opacity(0.55))
            Button(model.trf("pane.startAgent", session.agent.displayName)) {
                model.start(session.id)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var exitedOverlay: some View {
        HStack(spacing: 8) {
            Text(session.activity == .failed ? model.tr("pane.processFailed") : model.tr("pane.processExited"))
            Button(model.tr("pane.restart")) { model.restart(session.id) }
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
