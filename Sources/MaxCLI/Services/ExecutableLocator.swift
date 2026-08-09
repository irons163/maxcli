import Foundation

struct ExecutableLocator {
    private let environment: [String: String]
    private let homeDirectory: String
    private let additionalSearchPaths: [String]
    private let fileManager: FileManager

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil,
        additionalSearchPaths: [String]? = nil,
        fileManager: FileManager = .default
    ) {
        let home = homeDirectory ?? fileManager.homeDirectoryForCurrentUser.path
        self.environment = environment
        self.homeDirectory = home
        self.additionalSearchPaths = additionalSearchPaths ?? [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.opencode/bin",
            "\(home)/.cargo/bin",
            "\(home)/.npm-global/bin"
        ]
        self.fileManager = fileManager
    }

    func path(for agent: AgentKind) -> String? {
        let executable = agent.executable
        guard !executable.isEmpty else { return nil }
        if executable.hasPrefix("/") {
            return fileManager.isExecutableFile(atPath: executable) ? executable : nil
        }

        for directory in searchPaths {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(executable).path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    var installedAgents: Set<AgentKind> {
        Set(AgentKind.allCases.filter { $0 == .custom || path(for: $0) != nil })
    }

    private var searchPaths: [String] {
        var values = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        values.append(contentsOf: additionalSearchPaths)
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
