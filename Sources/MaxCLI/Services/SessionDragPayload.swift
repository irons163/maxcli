import Foundation
import UniformTypeIdentifiers

/// Custom pasteboard type for dragging sessions between the sidebar and grid.
/// Using a dedicated UTI (instead of plain text) prevents unrelated drags —
/// e.g. files from Finder, which also carry a plain-text path representation —
/// from triggering session reorder/group drops.
enum SessionDragPayload {
    static let typeIdentifier = "dev.maxcli.session-id"

    static var dropTypes: [UTType] {
        [UTType(typeIdentifier)].compactMap { $0 }.isEmpty ? [.plainText] : [UTType(typeIdentifier)!]
    }

    static func provider(for sessionID: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion in
            completion(sessionID.uuidString.data(using: .utf8), nil)
            return nil
        }
        return provider
    }

    static func sessionID(from provider: NSItemProvider, completion: @escaping @MainActor (UUID?) -> Void) {
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            let id = data
                .flatMap { String(data: $0, encoding: .utf8) }
                .flatMap(UUID.init(uuidString:))
            Task { @MainActor in completion(id) }
        }
    }
}
