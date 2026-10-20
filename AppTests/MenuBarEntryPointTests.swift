import XCTest
@testable import CoolCumber

final class MenuBarEntryPointTests: XCTestCase {
    @MainActor
    func testUniversalMenuBarEntryPointInstallsWithoutDisplayGeometry() {
        let manager = MenuBarManager.shared

        manager.setup()
        manager.setup()

        XCTAssertTrue(manager.isUniversalEntryPointInstalled)
        XCTAssertEqual(
            MenuBarManager.primaryStatusItemAccessibilityIdentifier,
            "coolcumber.menuBar.primary"
        )
    }
}
