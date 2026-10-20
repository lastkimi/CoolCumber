#if !BETA
import AppKit
import XCTest

/// Captures the real, visible App Store target. These tests intentionally do
/// not inject telemetry fixtures: unavailable readings must remain visibly
/// unavailable, while supported values come from the running Mac.
final class StoreScreenshots: XCTestCase {
    private let captureFrame = CGRect(x: 48, y: 48, width: 1280, height: 800)
    private let frameTolerance: CGFloat = 2

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func test01EnglishOverview() {
        capture(
            language: "en",
            destination: "--open-main-window",
            attachmentName: "01-overview-en",
            windowTitle: "Overview",
            topAnchorIdentifier: "coolcumber.page.overview.top",
            requiredText: [
                "Overview", "Cooling", "Activity", "History", "Battery",
                "Maintenance", "Settings"
            ]
        )
    }

    func test02EnglishHistory() {
        capture(
            language: "en",
            destination: "--open-history",
            attachmentName: "02-history-en",
            windowTitle: "History",
            topAnchorIdentifier: "coolcumber.page.history.top",
            requiredText: [
                "Free: up to 24 hours of local history", "Export CSV — Pro"
            ],
            primaryCTA: "View Pro"
        )
    }

    func test03EnglishPro() {
        capture(
            language: "en",
            destination: "--open-pro",
            attachmentName: "03-pro-en",
            windowTitle: "Overview",
            topAnchorIdentifier: "coolcumber.paywall.title",
            requiredText: [
                "Your access", "What is included", "Restore purchases", "Free", "Pro"
            ],
            primaryCTA: "Unlock Pro — $19.99",
            paywall: PaywallExpectation(openButton: "View Pro", closeButton: "Close")
        )
    }

    func test04ChineseOverview() {
        capture(
            language: "zh",
            destination: "--open-main-window",
            attachmentName: "01-overview-zh",
            windowTitle: "概览",
            topAnchorIdentifier: "coolcumber.page.overview.top",
            requiredText: [
                "概览", "散热", "活动", "历史", "电池", "维护", "设置"
            ]
        )
    }

    func test05ChineseHistory() {
        capture(
            language: "zh",
            destination: "--open-history",
            attachmentName: "02-history-zh",
            windowTitle: "历史",
            topAnchorIdentifier: "coolcumber.page.history.top",
            requiredText: [
                "Free：最长 24 小时本地历史", "导出 CSV — Pro"
            ],
            primaryCTA: "查看 Pro"
        )
    }

    func test06ChinesePro() {
        capture(
            language: "zh",
            destination: "--open-pro",
            attachmentName: "03-pro-zh",
            windowTitle: "概览",
            topAnchorIdentifier: "coolcumber.paywall.title",
            requiredText: ["你的权益", "包含内容", "恢复购买", "Free", "Pro"],
            primaryCTA: "解锁 Pro — $19.99",
            paywall: PaywallExpectation(openButton: "了解 Pro", closeButton: "关闭")
        )
    }

    private func capture(
        language: String,
        destination: String,
        attachmentName: String,
        windowTitle: String,
        topAnchorIdentifier: String,
        requiredText: [String],
        primaryCTA: String? = nil,
        paywall: PaywallExpectation? = nil
    ) {
        let app = XCUIApplication()
        app.launchArguments = [
            "--skip-welcome",
            "--store-screenshot",
            destination,
            "--ui-language-\(language)",
            "--ui-appearance-dark",
            "-NSDisablePersistentUI", "YES",
            "-NSQuitAlwaysKeepsWindows", "NO"
        ]
        app.launch()
        defer { app.terminate() }

        // NavigationSplitView adopts the selected page title (for example,
        // "Overview") as the native NSWindow title, so select the actual main
        // window rather than relying on a static title string.
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20), "CoolCumber window did not appear")
        XCTAssertTrue(
            app.windows[windowTitle].waitForExistence(timeout: 20),
            "Unexpected native window/page title: \(windowTitle)"
        )
        app.activate()

        // A modal sheet prevents moving its parent. Close the launch-requested
        // sheet, normalize the real app window, then reopen the same product
        // sheet through its user-visible toolbar action.
        if let paywall {
            let launchClose = exactButton(paywall.closeButton, in: app)
            XCTAssertTrue(launchClose.waitForExistence(timeout: 20))
            assertFullyVisible(launchClose, within: window, name: paywall.closeButton)
            launchClose.click()
            XCTAssertTrue(launchClose.waitForNonExistence(timeout: 10))
        }

        normalize(window: window)
        assertWindowChrome(window)

        if let paywall {
            let open = exactButton(paywall.openButton, in: app)
            XCTAssertTrue(open.waitForExistence(timeout: 20), "Pro toolbar action was missing")
            XCTAssertTrue(open.isHittable, "Pro toolbar action was not hittable")
            open.click()

            let close = exactButton(paywall.closeButton, in: app)
            XCTAssertTrue(close.waitForExistence(timeout: 20), "Pro sheet close button was missing")
            let title = app.descendants(matching: .any)["coolcumber.paywall.title"]
            XCTAssertTrue(title.waitForExistence(timeout: 20), "Pro sheet title was missing")
            assertFullyVisible(close, within: window, name: paywall.closeButton)
            assertFullyVisible(title, within: window, name: "CoolCumber")
        }

        let anchor = app.descendants(matching: .any)[topAnchorIdentifier]
        XCTAssertTrue(
            anchor.waitForExistence(timeout: 20),
            "Top anchor was missing: \(topAnchorIdentifier)"
        )
        scrollToTop(containing: anchor, in: window)

        var layoutElements = [window, anchor]
        for text in requiredText {
            let element = exactElement(text, in: app)
            XCTAssertTrue(
                element.waitForExistence(timeout: 20),
                "Required product text was not visible: \(text)"
            )
            assertFullyVisible(element, within: window, name: text)
            layoutElements.append(element)
        }

        if let primaryCTA {
            let button = exactButton(primaryCTA, in: app)
            XCTAssertTrue(button.waitForExistence(timeout: 20), "Complete CTA was missing: \(primaryCTA)")
            XCTAssertTrue(button.isHittable, "CTA was not hittable: \(primaryCTA)")
            assertFullyVisible(button, within: window, name: primaryCTA)
            layoutElements.append(button)
        }

        waitForStableLayout(layoutElements)
        assertFrame(window.frame, matches: captureFrame, message: "Window moved before capture")
        print("STORE_SCREENSHOT_WINDOW_FRAME=\(window.frame)")

        let screenshot = window.screenshot()
        let bitmap = NSBitmapImageRep(data: screenshot.pngRepresentation)
        XCTAssertEqual(bitmap?.pixelsWide, 2560, "Screenshot was not 2560 pixels wide")
        XCTAssertEqual(bitmap?.pixelsHigh, 1600, "Screenshot was not 1600 pixels high")

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = attachmentName
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func normalize(window: XCUIElement) {
        guard let screen = NSScreen.main else {
            XCTFail("Screenshot runner could not resolve its main display")
            return
        }
        XCTAssertGreaterThanOrEqual(screen.frame.width, captureFrame.maxX)
        XCTAssertGreaterThanOrEqual(screen.frame.height, captureFrame.maxY)

        let close = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Native title bar controls were missing")
        move(window: window, to: captureFrame.origin)
        resize(window: window, to: captureFrame.size)
        move(window: window, to: captureFrame.origin)
        waitForStableLayout([window])
        assertFrame(window.frame, matches: captureFrame, message: "Could not normalize window")
    }

    private func move(window: XCUIElement, to origin: CGPoint) {
        let oldFrame = window.frame
        let delta = CGVector(dx: origin.x - oldFrame.minX, dy: origin.y - oldFrame.minY)
        guard abs(delta.dx) > frameTolerance || abs(delta.dy) > frameTolerance else { return }
        // XCUI does not expose a macOS title-bar element type. A point near
        // the top-centre of the native window is safely inside the draggable
        // title bar and away from the traffic-light and toolbar controls.
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.025))
        start.click(forDuration: 0.15, thenDragTo: start.withOffset(delta))
        waitForFrameChange(window, from: oldFrame)
    }

    private func resize(window: XCUIElement, to size: CGSize) {
        let oldFrame = window.frame
        let delta = CGVector(dx: size.width - oldFrame.width, dy: size.height - oldFrame.height)
        guard abs(delta.dx) > frameTolerance || abs(delta.dy) > frameTolerance else { return }
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -3, dy: -3))
        corner.click(forDuration: 0.15, thenDragTo: corner.withOffset(delta))
        waitForFrameChange(window, from: oldFrame)
    }

    private func scrollToTop(containing anchor: XCUIElement, in window: XCUIElement) {
        let matched = window.scrollViews.containing(.any, identifier: anchor.identifier).firstMatch
        let scrollView = matched.exists ? matched : window.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 10), "Page scroll view was missing")
        scrollView.scroll(byDeltaX: 0, deltaY: 4_000)
        waitForStableLayout([window, anchor])
        if !isFullyVisible(anchor, within: window) {
            scrollView.scroll(byDeltaX: 0, deltaY: -8_000)
            waitForStableLayout([window, anchor])
        }
        assertFullyVisible(anchor, within: window, name: anchor.identifier)
        XCTAssertLessThan(anchor.frame.midY, window.frame.midY, "Page was not scrolled to its top")
    }

    private func assertWindowChrome(_ window: XCUIElement) {
        let close = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Native close button was missing")
        XCTAssertTrue(close.isHittable, "Native close button was not hittable")
        assertFullyVisible(close, within: window, name: XCUIIdentifierCloseWindow)
    }

    private func exactElement(_ text: String, in root: XCUIElement) -> XCUIElement {
        root.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR value == %@", text, text))
            .firstMatch
    }

    private func exactButton(_ label: String, in root: XCUIElement) -> XCUIElement {
        root.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func waitForStableLayout(_ elements: [XCUIElement], timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        var previous = elements.map(\.frame)
        var stableSamples = 0
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
            let current = elements.map(\.frame)
            if zip(previous, current).allSatisfy({ framesMatch($0, $1) }) {
                stableSamples += 1
                if stableSamples >= 3 { return }
            } else {
                stableSamples = 0
            }
            previous = current
        }
        XCTFail("Screenshot layout did not settle within \(timeout) seconds")
    }

    private func waitForFrameChange(_ window: XCUIElement, from original: CGRect) {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if !framesMatch(window.frame, original) { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("Native window did not respond to the normalization drag")
    }

    private func assertFullyVisible(_ element: XCUIElement, within container: XCUIElement, name: String) {
        XCTAssertFalse(element.frame.isEmpty, "Element had no frame: \(name)")
        XCTAssertTrue(
            isFullyVisible(element, within: container),
            "Element was clipped: \(name); element=\(element.frame), window=\(container.frame)"
        )
    }

    private func isFullyVisible(_ element: XCUIElement, within container: XCUIElement) -> Bool {
        container.frame.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(element.frame)
    }

    private func assertFrame(_ actual: CGRect, matches expected: CGRect, message: String) {
        XCTAssertTrue(framesMatch(actual, expected), "\(message): expected \(expected), got \(actual)")
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= frameTolerance
            && abs(lhs.minY - rhs.minY) <= frameTolerance
            && abs(lhs.width - rhs.width) <= frameTolerance
            && abs(lhs.height - rhs.height) <= frameTolerance
    }
}

private struct PaywallExpectation {
    let openButton: String
    let closeButton: String
}
#endif
