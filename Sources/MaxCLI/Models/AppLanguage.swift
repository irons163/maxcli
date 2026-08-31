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

    private static let resourceBundle: Bundle = {
        let bundleName = "MaxCLI_MaxCLI.bundle"
        let candidateURLs = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent(bundleName)
        ].compactMap { $0 }

        if let bundle = candidateURLs.compactMap(Bundle.init(url:)).first {
            return bundle
        }

        // XCTest's main bundle is hosted by the test runner rather than the
        // package build directory, so use SwiftPM's generated accessor there.
        // In a production app, missing resources must degrade gracefully
        // instead of invoking Bundle.module's fatalError.
        #if DEBUG
        return .module
        #else
        return Bundle.main
        #endif
    }()

    var bundle: Bundle {
        guard let code else { return Self.resourceBundle }
        if let path = Self.resourceBundle.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        let root = Self.resourceBundle.bundlePath
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        if let name = contents.first(where: { $0.lowercased() == "\(code.lowercased()).lproj" }),
           let bundle = Bundle(path: root + "/" + name) {
            return bundle
        }
        return Self.resourceBundle
    }
}
