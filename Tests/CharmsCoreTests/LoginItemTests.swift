import XCTest
@testable import CharmsCore

final class LoginItemTests: XCTestCase {
    private let installed = "/Applications/Charms.app"
    /// Where macOS runs a downloaded app that was opened without being moved.
    private let translocated = "/private/var/folders/9k/2x0000gn/T/AppTranslocation/6C1B6F0A-4F7B-4D2A-9E0B-0C3F8A1D2E4F/d/Charms.app"

    func testAnAppThatNeverRegisteredCanBeSwitchedOn() {
        // An installed app whose login item was never registered reports
        // "not found", not "not registered". The switch once treated that as
        // "not in the Applications folder" and could not be used at all.
        XCTAssertEqual(LoginItem.state(for: .notFound, bundlePath: installed), .off)
        XCTAssertEqual(LoginItem.state(for: .notRegistered, bundlePath: installed), .off)
    }

    func testTheLocationOfTheAppDoesNotBlockTheSwitch() {
        for path in ["/Users/someone/Applications/Charms.app", "/Users/someone/Developer/Charms/dist/Charms.app", "/Volumes/Tools/Charms.app"] {
            XCTAssertEqual(LoginItem.state(for: .notFound, bundlePath: path), .off, path)
            XCTAssertEqual(LoginItem.state(for: .notRegistered, bundlePath: path), .off, path)
        }
    }

    func testARegisteredItemIsShownAsTheSystemReportsIt() {
        XCTAssertEqual(LoginItem.state(for: .enabled, bundlePath: installed), .on)
        XCTAssertEqual(LoginItem.state(for: .requiresApproval, bundlePath: installed), .needsApproval)
    }

    func testATranslocatedAppCannotRegister() {
        XCTAssertTrue(LoginItem.isTranslocated(translocated))
        XCTAssertFalse(LoginItem.isTranslocated(installed))
        XCTAssertEqual(LoginItem.state(for: .notFound, bundlePath: translocated), .unavailable)
        XCTAssertEqual(LoginItem.state(for: .notRegistered, bundlePath: translocated), .unavailable)
    }

    func testARegisteredItemCanStillBeSwitchedOffFromATranslocatedApp() {
        XCTAssertEqual(LoginItem.state(for: .enabled, bundlePath: translocated), .on)
        XCTAssertEqual(LoginItem.state(for: .requiresApproval, bundlePath: translocated), .needsApproval)
    }
}
