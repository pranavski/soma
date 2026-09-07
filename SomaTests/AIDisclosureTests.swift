import XCTest
@testable import Soma

/// The consent gate is the thing standing between the app and a 5.1.2(i)
/// rejection, so its state machine gets tests: it must start unanswered,
/// persist a decision across launches, and come back unanswered after a
/// reset (sign-out / account deletion).
@MainActor
final class AIDisclosureTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "soma.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStartsUnanswered() {
        let d = AIDisclosure(defaults: defaults)
        XCTAssertFalse(d.hasAnswered)
        XCTAssertFalse(d.hasConsented, "no consent until the user gives it")
    }

    func testAcceptPersistsAcrossLaunches() {
        AIDisclosure(defaults: defaults).accept()

        let relaunched = AIDisclosure(defaults: defaults)
        XCTAssertTrue(relaunched.hasAnswered)
        XCTAssertTrue(relaunched.hasConsented)
    }

    /// Declining is a real answer — the sheet must not reappear every launch,
    /// but nothing may be sent to Anthropic either.
    func testDeclinePersistsAndWithholdsConsent() {
        AIDisclosure(defaults: defaults).decline()

        let relaunched = AIDisclosure(defaults: defaults)
        XCTAssertTrue(relaunched.hasAnswered, "a decline is answered, not pending")
        XCTAssertFalse(relaunched.hasConsented)
    }

    func testConsentIsRevocable() {
        let d = AIDisclosure(defaults: defaults)
        d.accept()
        XCTAssertTrue(d.hasConsented)

        d.decline()
        XCTAssertFalse(d.hasConsented)
        XCTAssertFalse(AIDisclosure(defaults: defaults).hasConsented)
    }

    /// Sign-out resets to unanswered so the next account on this phone is
    /// asked rather than inheriting the previous user's decision.
    func testResetReturnsToUnanswered() {
        let d = AIDisclosure(defaults: defaults)
        d.accept()
        d.reset()

        XCTAssertFalse(d.hasAnswered)
        XCTAssertFalse(d.hasConsented)
        XCTAssertFalse(AIDisclosure(defaults: defaults).hasAnswered)
    }
}
