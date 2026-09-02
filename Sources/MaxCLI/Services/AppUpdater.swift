import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

enum AppUpdateArchitecture: Equatable {
    case appleSilicon
    case intel
    case unknown

    static var current: Self {
        #if arch(arm64)
        .appleSilicon
        #elseif arch(x86_64)
        .intel
        #else
        .unknown
        #endif
    }
}

enum AppUpdateFeed {
    static let repository = "irons163/maxcli"

    static func assetName(for architecture: AppUpdateArchitecture) -> String {
        switch architecture {
        case .appleSilicon, .unknown:
            return "appcast-arm64.xml"
        case .intel:
            return "appcast-x86_64.xml"
        }
    }

    static func url(for architecture: AppUpdateArchitecture) -> URL {
        let assetName = assetName(for: architecture)
        return URL(string: "https://github.com/\(repository)/releases/latest/download/\(assetName)")!
    }
}

@MainActor
final class AppUpdater: NSObject {
    static let shared = AppUpdater()

    #if canImport(Sparkle)
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    var isAvailable: Bool { true }

    func start() {
        let updater = updaterController.updater
        guard updater.automaticallyChecksForUpdates else { return }
        // Sparkle normally waits for its scheduled interval before checking.
        // Run one background check at launch so a newly published release can
        // be discovered without requiring the user to open the menu.
        updater.checkForUpdatesInBackground()
    }

    func checkForUpdates() {
        guard updaterController.updater.canCheckForUpdates else { return }
        updaterController.checkForUpdates(nil)
    }
    #else
    var isAvailable: Bool { false }

    func start() {}

    func checkForUpdates() {}
    #endif

    private override init() {
        super.init()
    }
}

#if canImport(Sparkle)
extension AppUpdater: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        AppUpdateFeed.url(for: AppUpdateArchitecture.current).absoluteString
    }
}
#endif
