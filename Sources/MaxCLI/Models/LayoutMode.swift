import Foundation

enum LayoutMode: String, Codable, CaseIterable, Identifiable {
    case focus
    case grid

    var id: String { rawValue }
    var title: String { self == .focus ? "Focus" : "Grid" }
    var symbolName: String { self == .focus ? "rectangle" : "square.grid.2x2" }
}
