import Foundation

enum LayoutMode: String, Codable, CaseIterable, Identifiable {
    case focus
    case grid
    case active

    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .focus: "menu.layout.focus"
        case .grid: "menu.layout.grid"
        case .active: "menu.layout.active"
        }
    }
    var symbolName: String {
        switch self {
        case .focus: "rectangle"
        case .grid: "square.grid.2x2"
        case .active: "bolt"
        }
    }
    var next: LayoutMode {
        let all = LayoutMode.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}
