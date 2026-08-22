import Foundation

struct SessionPersistence {
    private let defaults: UserDefaults
    private let key = "maxcli.sessions.v1"
    private let backupKey = "maxcli.sessions.v1.backup"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    struct LoadResult {
        var sessions: [WorkspaceSession]
        /// True when the primary store existed but could not be decoded in full.
        /// Persisting then would silently destroy recoverable data.
        var decodeFailed: Bool
    }

    func load() -> LoadResult {
        let decoder = JSONDecoder()
        guard let primary = defaults.data(forKey: key) else {
            if let backup = defaults.data(forKey: backupKey),
               let sessions = decodeAll(backup, decoder: decoder) {
                return LoadResult(sessions: sessions, decodeFailed: false)
            }
            return LoadResult(sessions: [], decodeFailed: false)
        }
        if let sessions = decodeAll(primary, decoder: decoder) {
            return LoadResult(sessions: sessions, decodeFailed: false)
        }
        if let backup = defaults.data(forKey: backupKey),
           let sessions = decodeAll(backup, decoder: decoder) {
            return LoadResult(sessions: sessions, decodeFailed: true)
        }
        return LoadResult(sessions: [], decodeFailed: true)
    }

    func save(_ sessions: [WorkspaceSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        if let existing = defaults.data(forKey: key), existing != data {
            defaults.set(existing, forKey: backupKey)
        }
        defaults.set(data, forKey: key)
    }

    private func decodeAll(_ data: Data, decoder: JSONDecoder) -> [WorkspaceSession]? {
        if let sessions = try? decoder.decode([WorkspaceSession].self, from: data) {
            return restored(sessions)
        }
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        let salvaged = array.compactMap { element -> WorkspaceSession? in
            guard let elementData = try? JSONSerialization.data(withJSONObject: element),
                  var session = try? decoder.decode(WorkspaceSession.self, from: elementData)
            else { return nil }
            session.activity = .stopped
            return session
        }
        return salvaged.isEmpty ? nil : salvaged
    }

    private func restored(_ sessions: [WorkspaceSession]) -> [WorkspaceSession] {
        sessions.filter { !$0.isTransient }.map { session in
            var restored = session
            restored.activity = .stopped
            return restored
        }
    }
}
