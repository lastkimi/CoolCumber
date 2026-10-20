#if BETA
import XCTest

/// Exercises the actual optimized Beta app without StoreKit fixtures or
/// injected entitlements. A Beta must expose temporary access and no payments.
final class BetaAccessSmokeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testBetaPaywallShowsTemporaryAccessWithoutPurchaseOrRestore() {
        let app = launch(destination: "--open-pro")
        defer { app.terminate() }

        let access = element(
            matching: "label == 'Current access: Beta Preview' OR label == '当前权益：免费 Beta'",
            in: app
        )
        XCTAssertTrue(access.waitForExistence(timeout: 20))
        let explanation = element(
            matching: "label CONTAINS 'It is not a purchase' OR value CONTAINS 'It is not a purchase' OR label CONTAINS '这不是购买' OR value CONTAINS '这不是购买'",
            in: app
        )
        XCTAssertTrue(explanation.waitForExistence(timeout: 20))
        XCTAssertFalse(element(
            matching: "label BEGINSWITH 'Unlock Pro —' OR label BEGINSWITH '解锁 Pro —'",
            in: app
        ).exists)
        XCTAssertFalse(element(
            matching: "label == 'Restore purchases' OR label == '恢复购买'",
            in: app
        ).exists)
        attach(window: app.windows.firstMatch, name: "Beta temporary access, no payment")
    }

    func testBetaHistoryExposesTemporaryThirtyDayAccessAndExport() {
        let app = launch(destination: "--open-history")
        defer { app.terminate() }

        XCTAssertTrue(element(
            matching: "label == 'Free Beta: 30-day history temporarily enabled' OR value == 'Free Beta: 30-day history temporarily enabled' OR label == '免费 Beta：30 天历史已临时启用' OR value == '免费 Beta：30 天历史已临时启用'",
            in: app
        ).waitForExistence(timeout: 20))
        XCTAssertTrue(element(
            matching: "label == 'Export CSV…' OR label == '导出 CSV…'",
            in: app
        ).waitForExistence(timeout: 20))
        XCTAssertFalse(element(
            matching: "label == 'Export CSV — Pro' OR label == '导出 CSV — Pro'",
            in: app
        ).exists)
        attach(window: app.windows.firstMatch, name: "Beta thirty-day history and export")
    }

    private func launch(destination: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-welcome", destination]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(
            app.statusItems["coolcumber.menuBar.primary"].waitForExistence(timeout: 20),
            "The universal menu-bar entry point was not installed"
        )
        return app
    }

    private func element(matching predicate: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: predicate))
            .firstMatch
    }

    private func attach(window: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
