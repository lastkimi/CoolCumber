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
        let app = launch(destination: "--open-main-window")
        defer { app.terminate() }
        let proEntry = app.buttons.matching(NSPredicate(
            format: "label == 'Pro active' OR label == 'Pro 已启用' OR label == 'View Pro' OR label == '了解 Pro'"
        )).firstMatch
        XCTAssertTrue(proEntry.waitForExistence(timeout: 20))
        proEntry.click()
        XCTAssertTrue(app.staticTexts["coolcumber.paywall.title"].waitForExistence(timeout: 20))
        attach(window: app.windows.firstMatch, name: "Beta payment-page entry")

        let access = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'Beta Preview' OR value CONTAINS 'Beta Preview' OR label CONTAINS '免费 Beta' OR value CONTAINS '免费 Beta'"
        )).firstMatch
        let hasBetaAccess = access.waitForExistence(timeout: 20)
        if !hasBetaAccess { print(app.debugDescription) }
        XCTAssertTrue(hasBetaAccess)
        let explanation = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'not a purchase' OR value CONTAINS 'not a purchase' OR label CONTAINS '这不是购买' OR value CONTAINS '这不是购买'"
        )).firstMatch
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
        app.windows.firstMatch.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -1_200)
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
        app.activate()
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
