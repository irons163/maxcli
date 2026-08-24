import XCTest
@testable import MaxCLI

final class AppUpdaterTests: XCTestCase {
    func testFeedAssetNameByArchitecture() {
        XCTAssertEqual(AppUpdateFeed.assetName(for: .appleSilicon), "appcast-arm64.xml")
        XCTAssertEqual(AppUpdateFeed.assetName(for: .intel), "appcast-x86_64.xml")
        XCTAssertEqual(AppUpdateFeed.assetName(for: .unknown), "appcast-arm64.xml")
    }

    func testFeedURLUsesHTTPSAndMaxCLIReleaseAsset() {
        let url = AppUpdateFeed.url(for: .appleSilicon)

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/irons163/maxcli/releases/latest/download/appcast-arm64.xml")
    }
}
