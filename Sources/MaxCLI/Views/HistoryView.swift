import SwiftUI

@MainActor
final class HistoryModel: ObservableObject {
    @Published private(set) var sessions: [OpenCodeHistorySession] = []
    @Published private(set) var selectedSessionID: String?
    @Published private(set) var transcript: OpenCodeTranscript?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var searchText = ""

    var databasePath: String {
        OpenCodeHistoryStore.databaseURL?.path ?? "~/.local/share/opencode/opencode.db"
    }

    var filteredSessions: [OpenCodeHistorySession] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return sessions }
        return sessions.filter { session in
            session.title.lowercased().contains(query)
                || session.directory.lowercased().contains(query)
                || (session.agent?.lowercased().contains(query) ?? false)
        }
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await Task.detached {
                try OpenCodeHistoryStore.listSessions()
            }.value
            sessions = loaded
            if let selectedSessionID, !loaded.contains(where: { $0.id == selectedSessionID }) {
                self.selectedSessionID = nil
            }
            if let current = selectedSessionID {
                await loadTranscript(for: current)
            } else if let first = loaded.first {
                selectedSessionID = first.id
                await loadTranscript(for: first.id)
            } else {
                transcript = nil
            }
        } catch {
            errorMessage = error.localizedDescription
            sessions = []
            transcript = nil
        }
        isLoading = false
    }

    func select(_ session: OpenCodeHistorySession) {
        guard session.id != selectedSessionID else { return }
        selectedSessionID = session.id
        Task { await loadTranscript(for: session.id) }
    }

    private func loadTranscript(for sessionID: String) async {
        transcript = nil
        do {
            let loaded = try await Task.detached {
                try OpenCodeHistoryStore.transcript(for: sessionID)
            }.value
            guard selectedSessionID == sessionID else { return }
            transcript = loaded
        } catch {
            guard selectedSessionID == sessionID else { return }
            errorMessage = error.localizedDescription
        }
    }
}

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = HistoryModel()

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            transcriptDetail
        }
        .navigationTitle("opencode History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                }
                .help("Close history")
            }
        }
        .task {
            await model.reload()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            if model.sessions.isEmpty {
                emptySidebar
            } else {
                TextField("搜尋紀錄", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(10)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.filteredSessions) { session in
                            HistorySessionRow(
                                session: session,
                                isSelected: model.selectedSessionID == session.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.select(session)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 360)
    }

    @ViewBuilder
    private var emptySidebar: some View {
        if let errorMessage = model.errorMessage {
            ContentUnavailableView {
                Label("無法讀取紀錄", systemImage: "exclamationmark.triangle")
            } description: {
                Text("\(errorMessage)\n\(model.databasePath)")
            } actions: {
                Button("重試") {
                    Task { await model.reload() }
                }
            }
        } else {
            ContentUnavailableView {
                Label("沒有紀錄", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("還沒有找到 opencode 對話紀錄\n\(model.databasePath)")
            }
        }
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcriptDetail: some View {
        if model.isLoading, model.transcript == nil {
            ProgressView("載入中…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let transcript = model.transcript {
            TranscriptView(transcript: transcript)
        } else if let errorMessage = model.errorMessage {
            ContentUnavailableView {
                Label("讀取失敗", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            }
        } else {
            ContentUnavailableView("選擇一個 session", systemImage: "bubble.left.and.bubble.right")
        }
    }
}

private struct HistorySessionRow: View {
    let session: OpenCodeHistorySession
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(session.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if session.isSubagent {
                    Text("sub")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            Text(detailLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.17) : Color.clear)
        }
    }

    private var detailLine: String {
        let directory = URL(fileURLWithPath: session.directory).lastPathComponent
        let agent = session.agent ?? "opencode"
        let date = session.timeUpdated.formatted(.relative(presentation: .named))
        return "\(agent) · \(directory) · \(session.messageCount) 則 · \(date)"
    }
}

private struct TranscriptView: View {
    let transcript: OpenCodeTranscript

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                ForEach(transcript.messages) { message in
                    MessageBlock(message: message)
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(transcript.session.title)
                .font(.title2.weight(.semibold))
            Text(headerLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var headerLine: String {
        let directory = URL(fileURLWithPath: transcript.session.directory).lastPathComponent
        let created = transcript.session.timeCreated.formatted(date: .abbreviated, time: .shortened)
        return "\(transcript.session.agent ?? "opencode") · \(directory) · \(transcript.messages.count) 則 · \(created)"
    }
}

private struct MessageBlock: View {
    let message: OpenCodeMessage

    private var displayableParts: [OpenCodePart] {
        message.parts.filter(\.isDisplayable)
    }

    var body: some View {
        let parts = displayableParts
        let textParts = parts.filter { $0.kind == .text }
        let otherParts = parts.filter { $0.kind != .text }
        if !parts.isEmpty || message.role == "user" {
            VStack(alignment: .leading, spacing: 8) {
                if isUser {
                    Text("你")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text(message.role == "system" ? "System" : (message.role == "tool" ? "Tool" : "Assistant"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ForEach(textParts) { part in
                    PartView(part: part)
                }

                if !otherParts.isEmpty {
                    OtherPartsDisclosure(parts: otherParts)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isUser ? Color.accentColor.opacity(0.08) : Color.clear)
            .overlay(alignment: .bottom) {
                Divider().opacity(0.4)
            }
        }
    }

    private var isUser: Bool {
        message.role == "user"
    }
}

private struct OtherPartsDisclosure: View {
    let parts: [OpenCodePart]

    private var toolCount: Int { parts.filter { $0.kind == .tool }.count }
    private var reasoningCount: Int { parts.filter { $0.kind == .reasoning }.count }
    private var fileCount: Int { parts.filter { $0.kind == .file || $0.kind == .patch }.count }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(parts) { part in
                    if part.kind == .reasoning, let text = part.text, !text.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("思考", systemImage: "brain")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(text)
                                .font(.callout)
                                .italic()
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        PartView(part: part)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Label(summary, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        var segments: [String] = []
        if toolCount > 0 { segments.append("\(toolCount) 個工具呼叫") }
        if reasoningCount > 0 { segments.append("\(reasoningCount) 段思考") }
        if fileCount > 0 { segments.append("\(fileCount) 個檔案") }
        return segments.isEmpty ? "其他內容" : segments.joined(separator: " · ")
    }

    private var icon: String {
        if toolCount > 0 { return "wrench.and.screwdriver" }
        if reasoningCount > 0 { return "brain" }
        return "paperclip"
    }
}

private struct PartView: View {
    let part: OpenCodePart

    var body: some View {
        switch part.kind {
        case .text:
            if let text = part.text {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .reasoning:
            if let text = part.text, !text.isEmpty {
                DisclosureGroup {
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .italic()
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("思考過程", systemImage: "brain")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        case .tool:
            ToolPartView(part: part)
        case .file:
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                Text(part.filename ?? "file")
                    .font(.caption)
                    .textSelection(.enabled)
            }
            .foregroundStyle(.secondary)
        case .patch:
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                Text(part.patchFiles.joined(separator: " · "))
                    .font(.caption)
                    .textSelection(.enabled)
            }
            .foregroundStyle(.secondary)
        case .stepStart, .stepFinish, .compaction, .unknown:
            EmptyView()
        }
    }
}

private struct ToolPartView: View {
    let part: OpenCodePart

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if let input = part.toolInput {
                    LabeledContent("Input") {
                        CodeText(input, limit: 400)
                    }
                    .labelStyle(.titleOnly)
                }
                if let output = part.toolOutput {
                    LabeledContent("Output") {
                        CodeText(output, limit: 800)
                    }
                    .labelStyle(.titleOnly)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 11))
                Text(part.toolName ?? "tool")
                    .font(.caption.weight(.medium))
                if let status = part.toolStatus {
                    Text(status)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(statusColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(statusColor)
                }
            }
            .foregroundStyle(.primary)
        }
        .font(.caption)
    }

    private var statusColor: Color {
        switch part.toolStatus {
        case "running", "pending": .orange
        case "completed", "success": .green
        case "error", "failed": .red
        default: .secondary
        }
    }
}

private struct CodeText: View {
    let text: String
    let limit: Int

    init(_ text: String, limit: Int) {
        self.text = text
        self.limit = limit
    }

    var body: some View {
        Text(displayText)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .lineLimit(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }

    private var displayText: String {
        text.count > limit ? String(text.prefix(limit)) + "\n…" : text
    }
}
