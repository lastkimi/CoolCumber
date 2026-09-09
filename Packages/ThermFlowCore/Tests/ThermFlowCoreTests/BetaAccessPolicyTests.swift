import Foundation
import XCTest
@testable import ThermFlowCore

final class BetaAccessPolicyTests: XCTestCase {
    func testAllowsOnlyInsideBoundedConfiguredWindow() {
        let startsAt = TestFixtures.date
        let expiresAt = startsAt.addingTimeInterval(30 * 24 * 60 * 60)
        let policy = BetaAccessPolicy()

        XCTAssertEqual(
            policy.status(startsAt: startsAt, expiresAt: expiresAt, at: startsAt),
            .active(expiresAt: expiresAt)
        )
        XCTAssertEqual(
            policy.status(startsAt: startsAt, expiresAt: expiresAt, at: expiresAt),
            .expired(expiresAt: expiresAt)
        )
    }

    func testFailsClosedForMissingOrExcessiveWindow() {
        let startsAt = TestFixtures.date
        let tooLate = startsAt.addingTimeInterval(BetaAccessPolicy.maximumDuration + 1)
        let policy = BetaAccessPolicy()

        XCTAssertEqual(
            policy.status(startsAt: nil, expiresAt: tooLate, at: startsAt),
            .invalidConfiguration
        )
        XCTAssertEqual(
            policy.status(startsAt: startsAt, expiresAt: tooLate, at: startsAt),
            .invalidConfiguration
        )
    }

    func testReportsNotStartedBeforeWindow() {
        let startsAt = TestFixtures.date
        let policy = BetaAccessPolicy()
        XCTAssertEqual(
            policy.status(
                startsAt: startsAt,
                expiresAt: startsAt.addingTimeInterval(60),
                at: startsAt.addingTimeInterval(-1)
            ),
            .notStarted(startsAt: startsAt)
        )
    }
}
