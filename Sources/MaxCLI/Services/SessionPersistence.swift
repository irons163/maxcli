import Foundation

struct SessionPersistence {
    private let defaults: UserDefaults
    private let key = "maxcli.sessions.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [WorkspaceSession] {
        guard let data = defaults.data(forKey: key),
              let sessions = try? JSONDecoder().decode([WorkspaceSession].self, from: data)
        else { return [] }
        return sessions.map { session in
            var restored = session
            restored.activity = .stopped
            return restored
        }
    }

    func save(_ sessions: [WorkspaceSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: key)
    }
}
