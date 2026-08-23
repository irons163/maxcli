import Foundation

@MainActor
enum OpenCodeModels {
    private static var cache: [String]?

    static func load() async -> [String] {
        if let cache { return cache }
        let list = await Task.detached { run() }.value
        cache = list
        return list
    }

    static func invalidate() {
        cache = nil
    }

    private nonisolated static func run() -> [String] {
        let executable = ExecutableLocator().path(for: .opencode)
            ?? NSHomeDirectory() + "/.opencode/bin/opencode"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["models"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            return output
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
                .filter { !$0.isEmpty && !$0.contains(" ") }
                .sorted()
        } catch {
            return []
        }
    }
}
