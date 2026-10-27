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
                "Overview", "Activity", "Thermal check", "History", "Battery",
                "Sensor access", "Data & privacy", "Settings"
            ]
        )
    }

    func test02EnglishActivity() {
        capture(language: "en", destination: "--open-activity", attachmentName: "02-activity-en",
                windowTitle: "Activity", topAnchorIdentifier: "coolcumber.metric.cpu",
                requiredText: ["CPU usage", "Memory use", "Storage use"], primaryCTA: "Compare a workload change")
    }

    func test03EnglishCheck() {
        capture(language: "en", destination: "--open-check", attachmentName: "03-check-live-en",
                windowTitle: "Thermal check", topAnchorIdentifier: "coolcumber.check.top",
                requiredText: ["Baseline", "Follow-up"], primaryCTA: "Finish check", recordRealCheck: true)
    }

    func test04EnglishHistory() {
        capture(
            language: "en",
            destination: "--open-history",
            attachmentName: "05-history-en",
            windowTitle: "History",
            topAnchorIdentifier: "coolcumber.page.history.top",
            requiredText: [
                "Free: up to 24 hours of local history", "Export CSV — Pro"
            ],
            primaryCTA: "View Pro"
        )
    }

    func test05EnglishPro() {
        capture(
            language: "en",
            destination: "--open-pro",
            attachmentName: "06-pro-en",
            windowTitle: "Overview",
            topAnchorIdentifier: "coolcumber.paywall.title",
            requiredText: [
                "Your access", "What is included", "Restore purchases", "Free", "Pro"
            ],
            primaryCTAPrefix: "Unlock Pro — ",
            paywall: PaywallExpectation(openButton: "View Pro", closeButton: "Close")
        )
    }

    func test06ChineseOverview() {
        capture(
            language: "zh",
            destination: "--open-main-window",
            attachmentName: "01-overview-zh",
            windowTitle: "概览",
            topAnchorIdentifier: "coolcumber.page.overview.top",
            requiredText: [
                "概览", "活动", "热状态检查", "历史", "电池", "传感器权限", "数据与隐私", "设置"
            ]
        )
    }

    func test07ChineseActivity() {
        capture(language: "zh", destination: "--open-activity", attachmentName: "02-activity-zh",
                windowTitle: "活动", topAnchorIdentifier: "coolcumber.metric.cpu",
                requiredText: ["CPU 使用率", "内存使用", "存储使用"], primaryCTA: "对比一次负载变化")
    }

    func test08ChineseCheck() {
        capture(language: "zh", destination: "--open-check", attachmentName: "03-check-live-zh",
                windowTitle: "热状态检查", topAnchorIdentifier: "coolcumber.check.top",
                requiredText: ["基线", "对比阶段"], primaryCTA: "完成检查", recordRealCheck: true)
    }

    func test09ChineseHistory() {
        capture(
            language: "zh",
            destination: "--open-history",
            attachmentName: "05-history-zh",
            windowTitle: "历史",
            topAnchorIdentifier: "coolcumber.page.history.top",
            requiredText: [
                "Free：最长 24 小时本地历史", "导出 CSV — Pro"
            ],
            primaryCTA: "查看 Pro"
        )
    }

    func test10ChinesePro() {
        capture(
            language: "zh",
            destination: "--open-pro",
            attachmentName: "06-pro-zh",
            windowTitle: "概览",
            topAnchorIdentifier: "coolcumber.paywall.title",
            requiredText: ["你的权益", "包含内容", "恢复购买", "Free", "Pro"],
            primaryCTAPrefix: "解锁 Pro — ",
            paywall: PaywallExpectation(openButton: "了解 Pro", closeButton: "关闭")
        )
    }

    func test11NarrowWindowKeepsActionsAndTruthfulSensorBoundary() {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-welcome", "--store-screenshot", "--open-sensor-access", "--ui-language-en",
                               "--qa-storage-scope=\(UUID().uuidString)"]
        app.launch()
        defer { app.terminate() }
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        normalize(window: window)
        resize(window: window, to: CGSize(width: 940, height: 740))
        waitForStableLayout([window])
        let disclosure = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Temperature and fan readings are unsupported here")).firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 15), "The sandbox limitation must remain visible, not be stripped to look capable")
        let navigation = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Thermal check")).firstMatch
        XCTAssertTrue(navigation.waitForExistence(timeout: 15))
        navigation.click()
        let start = app.buttons["coolcumber.check.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        XCTAssertTrue(start.isHittable)
        assertFullyVisible(start, within: window, name: "Narrow-window footer action")
    }

    private func capture(
        language: String,
        destination: String,
        attachmentName: String,
        windowTitle: String,
        topAnchorIdentifier: String,
        requiredText: [String],
        primaryCTA: String? = nil,
        primaryCTAPrefix: String? = nil,
        paywall: PaywallExpectation? = nil,
        recordRealCheck: Bool = false
    ) {
        let app = XCUIApplication()
        let storageScope = UUID().uuidString
        print("NATIVE_CAPTURE_STORAGE_SCOPE=\(storageScope)")
        app.launchArguments = [
            "--skip-welcome",
            "--store-screenshot",
            destination,
            "--ui-language-\(language)",
            "--ui-appearance-dark",
            "--qa-storage-scope=\(storageScope)",
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

        if recordRealCheck {
            recordCheckUntilReadyToFinish(app: app, window: window, language: language)
        }
        if destination == "--open-activity" {
            waitForRealMetric("coolcumber.metric.cpu", in: app)
            waitForRealMetric("coolcumber.metric.memorychip", in: app)
        }
        if destination == "--open-history" {
            let count = app.staticTexts["coolcumber.history.record-count"]
            XCTAssertTrue(count.waitForExistence(timeout: 20))
            let predicate = NSPredicate(format: "label MATCHES %@", "^[1-9][0-9]* .*")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: count)], timeout: 30), .completed,
                           "The first real sample must not wait for the initial empty snapshot's five-minute throttle")
        }

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
        if let primaryCTAPrefix {
            let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", primaryCTAPrefix)).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 25), "StoreKit must return a real localized price, not a test-fixture or hardcoded currency")
            XCTAssertTrue(button.isEnabled)
            assertFullyVisible(button, within: window, name: button.label)
            print("STOREKIT_LOCALIZED_PURCHASE_TITLE=\(button.label)")
            layoutElements.append(button)
        }

        waitForStableLayout(layoutElements)
        assertFrame(window.frame, matches: captureFrame, message: "Window moved before capture")
        print("STORE_SCREENSHOT_WINDOW_FRAME=\(window.frame)")

        attachWindow(window, name: attachmentName)

        if recordRealCheck {
            app.buttons["coolcumber.check.advance"].click()
            let phase = app.staticTexts["coolcumber.check.phase"]
            waitForLabel(language == "zh" ? "检查已完成" : "Check complete", on: phase)
            waitForLabel(language == "zh" ? "已保存在本机" : "Saved locally", on: app.staticTexts["coolcumber.check.saved"])
            let summary = app.descendants(matching: .any)["coolcumber.check.summary"]
            XCTAssertTrue(summary.waitForExistence(timeout: 15))
            scrollToTop(containing: app.descendants(matching: .any)["coolcumber.check.top"], in: window)
            assertFullyVisible(summary, within: window, name: "Actual comparison summary")
            attachWindow(window, name: language == "zh" ? "04-check-report-zh" : "04-check-report-en")

            // Normal termination flushes the bounded document write. Relaunch
            // the same isolated namespace and verify real persistence, not a
            // view-state flag or an injected snapshot.
            app.terminate()
            app.launch()
            waitForLabel(language == "zh" ? "检查已完成" : "Check complete", on: app.staticTexts["coolcumber.check.phase"])
        }
    }

    private func attachWindow(_ window: XCUIElement, name: String) {
        let screenshot = window.screenshot()
        let bitmap = NSBitmapImageRep(data: screenshot.pngRepresentation)
        XCTAssertEqual(bitmap?.pixelsWide, 2560, "Screenshot was not 2560 pixels wide")
        XCTAssertEqual(bitmap?.pixelsHigh, 1600, "Screenshot was not 1600 pixels high")

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func recordCheckUntilReadyToFinish(app: XCUIApplication, window: XCUIElement, language: String) {
        let start = app.buttons["coolcumber.check.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.click()
        waitForLabel(language == "zh" ? "正在记录基线" : "Recording baseline", on: app.staticTexts["coolcumber.check.phase"])
        let advance = app.buttons["coolcumber.check.advance"]
        XCTAssertTrue(advance.waitForExistence(timeout: 20))
        assertFullyVisible(advance, within: window, name: "Phase action must stay above the safe area")
        waitUntilEnabled(advance)
        advance.click()
        waitForLabel(language == "zh" ? "正在记录对比阶段" : "Recording follow-up", on: app.staticTexts["coolcumber.check.phase"])
        waitUntilEnabled(advance)
        assertFullyVisible(advance, within: window, name: "Finish action")
    }

    private func waitUntilEnabled(_ element: XCUIElement) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element)], timeout: 90), .completed,
                       "Three real fresh observations spanning 20 seconds must arrive; no fast-forward or fake data is used")
        XCTAssertTrue(element.isEnabled)
    }

    private func waitForLabel(_ text: String, on element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 20))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: element)], timeout: 20), .completed)
    }

    private func waitForRealMetric(_ identifier: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 20))
        let ready = NSPredicate(format: "value MATCHES %@ AND NOT value CONTAINS %@ AND NOT value CONTAINS %@", "^[0-9]+([.,][0-9]+)? %.*", "Stale", "已过期")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: element)], timeout: 30), .completed,
                       "The native capture requires an actual CPU/memory reading")
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
