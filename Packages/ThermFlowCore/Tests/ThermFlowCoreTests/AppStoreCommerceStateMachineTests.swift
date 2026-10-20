import XCTest
@testable import ThermFlowCore

final class AppStoreCommerceStateMachineTests: XCTestCase {
    private let productID = "com.slmcamp.CoolCumber.pro.lifetime"

    private var machine: AppStoreCommerceStateMachine {
        AppStoreCommerceStateMachine(lifetimeProductID: productID)
    }

    func testOnlyMatchingActiveVerifiedEvidenceUnlocksPro() {
        XCTAssertEqual(
            machine.resolveEntitlement(from: [
                .verified(productID: "another.product", isRevoked: false),
                .verified(productID: productID, isRevoked: false)
            ]),
            .pro
        )
        let purchase = machine.purchaseTransition(
            for: .verified(productID: productID, isRevoked: false)
        )
        XCTAssertEqual(purchase, .unlockVerified)
        XCTAssertTrue(purchase.shouldFinishVerifiedTransaction)
        XCTAssertEqual(
            machine.transactionUpdateTransition(
                for: .verified(productID: productID, isRevoked: false)
            ),
            .refreshEntitlements(
                finishVerifiedTransaction: true,
                wasRevoked: false
            )
        )
    }

    func testUnverifiedEvidenceFailsClosedUnlessActiveVerifiedEvidenceExists() {
        let failure = AppStoreTransactionEvidence.unverified(
            productID: productID,
            reason: "signature rejected"
        )

        XCTAssertEqual(
            machine.resolveEntitlement(from: [failure]),
            .unavailable(reason: "signature rejected")
        )
        XCTAssertEqual(
            machine.purchaseTransition(
                for: .unverified(productID: productID, reason: "signature rejected")
            ),
            .rejectUnverified(reason: "signature rejected")
        )
        XCTAssertEqual(
            machine.transactionUpdateTransition(for: failure),
            .rejectUnverified(reason: "signature rejected")
        )
        XCTAssertEqual(
            machine.resolveEntitlement(from: [
                failure,
                .verified(productID: productID, isRevoked: false)
            ]),
            .pro
        )
    }

    func testRevokedEvidenceNeverUnlocksAndUpdateRequiresRefresh() {
        XCTAssertEqual(
            machine.resolveEntitlement(from: [
                .verified(productID: productID, isRevoked: true)
            ]),
            .free
        )
        let purchase = machine.purchaseTransition(
            for: .verified(productID: productID, isRevoked: true)
        )
        XCTAssertEqual(purchase, .rejectRevoked)
        XCTAssertTrue(purchase.shouldFinishVerifiedTransaction)
        XCTAssertEqual(
            machine.transactionUpdateTransition(
                for: .verified(productID: productID, isRevoked: true)
            ),
            .refreshEntitlements(
                finishVerifiedTransaction: true,
                wasRevoked: true
            )
        )
    }

    func testPendingAndCancelledPurchasesDoNotFinishOrUnlock() {
        let pending = machine.purchaseTransition(for: .pending)
        let cancelled = machine.purchaseTransition(for: .userCancelled)

        XCTAssertEqual(pending, .pending)
        XCTAssertFalse(pending.shouldFinishVerifiedTransaction)
        XCTAssertEqual(cancelled, .cancelled)
        XCTAssertFalse(cancelled.shouldFinishVerifiedTransaction)
    }

    func testRestoreMapsVerifiedFreeAndVerificationFailureDistinctly() {
        XCTAssertEqual(machine.restoreTransition(for: .pro), .restored)
        XCTAssertEqual(machine.restoreTransition(for: .free), .noVerifiedPurchase)
        XCTAssertEqual(
            machine.restoreTransition(for: .unavailable(reason: "invalid JWS")),
            .verificationFailed(reason: "invalid JWS")
        )
    }

    func testUnexpectedProductIsIgnoredForEntitlementAndPurchase() {
        XCTAssertEqual(
            machine.resolveEntitlement(from: [
                .unverified(productID: "another.product", reason: "irrelevant")
            ]),
            .free
        )
        XCTAssertEqual(
            machine.purchaseTransition(
                for: .verified(productID: "another.product", isRevoked: false)
            ),
            .rejectUnexpectedProduct
        )
        XCTAssertEqual(
            machine.transactionUpdateTransition(
                for: .verified(productID: "another.product", isRevoked: false)
            ),
            .ignore
        )
    }
}
