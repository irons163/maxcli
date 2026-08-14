import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case en
    case zhHant = "zh-Hant"
    case zhHans = "zh-Hans"
    case fr
    case es
    case ja
    case ko

    var id: String { rawValue }

    var code: String? {
        self == .system ? nil : rawValue
    }

    var displayName: String {
        switch self {
        case .system: "system"
        case .en: "English"
        case .zhHant: "繁體中文"
        case .zhHans: "简体中文"
        case .fr: "Français"
        case .es: "Español"
        case .ja: "日本語"
        case .ko: "한국어"
        }
    }

    var bundle: Bundle {
        guard let code else { return .module }
        if let path = Bundle.module.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        let root = Bundle.module.bundlePath
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        if let name = contents.first(where: { $0.lowercased() == "\(code.lowercased()).lproj" }),
           let bundle = Bundle(path: root + "/" + name) {
            return bundle
        }
        return .module
    }
}
