import Foundation

struct SessionPersistence {
    private let defaults: UserDefaults
    private let key = "maxcli.sessions.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [WorkspaceSession] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        if let sessions = try? decoder.decode([WorkspaceSession].self, from: data) {
            return sessions.map { restored in
                var session = restored
                session.activity = .stopped
                return session
            }
        }
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return array.compactMap { element in
            guard let elementData = try? JSONSerialization.data(withJSONObject: element),
                  var session = try? decoder.decode(WorkspaceSession.self, from: elementData)
            else { return nil }
            session.activity = .stopped
            return session
        }
    }

    func save(_ sessions: [WorkspaceSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: key)
    }
}
