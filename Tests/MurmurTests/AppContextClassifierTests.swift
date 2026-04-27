import XCTest
@testable import Murmur

final class AppContextClassifierTests: XCTestCase {
    func testClassifierDetectsCodeApps() {
        let classifier = AppContextClassifier()
        XCTAssertEqual(
            classifier.classify(bundleIdentifier: "com.getcursor.Cursor", localizedName: "Cursor"),
            .code
        )
    }

    func testClassifierDetectsTerminals() {
        let classifier = AppContextClassifier()
        XCTAssertEqual(
            classifier.classify(bundleIdentifier: "com.googlecode.iterm2", localizedName: "iTerm"),
            .terminal
        )
    }

    func testClassifierFallsBackToUnknown() {
        let classifier = AppContextClassifier()
        XCTAssertEqual(
            classifier.classify(bundleIdentifier: "com.example.RandomApp", localizedName: "RandomApp"),
            .unknown
        )
    }
}
