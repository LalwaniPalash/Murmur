import Foundation
import Testing
@testable import MurmurNext

struct BrowserDomainContextTests {
    @Test(arguments: [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
        "org.chromium.Chromium",
    ])
    func classifiesExactGmailHostForDeclaredBrowsers(bundleIdentifier: String) {
        let context = ApplicationContextClassifier().classify(
            bundleIdentifier: bundleIdentifier,
            applicationName: "Browser",
            activeBrowserURL: URL(string: "https://mail.google.com/mail/u/0/#inbox"),
            browserDomainDetectionAllowed: true
        )

        #expect(context == .email)
    }

    @Test(arguments: [
        "https://mail.google.com.evil.test/",
        "https://mail.google.com@evil.test/",
        "https://sub.mail.google.com/",
        "https://evilmail.google.com/",
        "http://mail.google.com/",
        "ftp://mail.google.com/",
        "https://xn--mal-google-43g.com/",
        "about:privatebrowsing",
    ])
    func spoofedSubdomainInsecureAndPrivateURLsStayBrowser(rawURL: String) {
        let context = ApplicationContextClassifier().classify(
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Google Chrome",
            activeBrowserURL: URL(string: rawURL),
            browserDomainDetectionAllowed: true
        )

        #expect(context == .browser)
    }

    @Test func missingConsentOrUnavailableURLStaysBrowser() {
        let classifier = ApplicationContextClassifier()
        let gmail = URL(string: "https://mail.google.com/")

        #expect(classifier.classify(
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            activeBrowserURL: gmail,
            browserDomainDetectionAllowed: false
        ) == .browser)
        #expect(classifier.classify(
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            activeBrowserURL: nil,
            browserDomainDetectionAllowed: true
        ) == .browser)
    }

    @Test func unsupportedApplicationsNeverBecomeEmailFromAURL() {
        #expect(ApplicationContextClassifier().classify(
            bundleIdentifier: "com.example.notes",
            applicationName: "Plain Notes",
            activeBrowserURL: URL(string: "https://mail.google.com/"),
            browserDomainDetectionAllowed: true
        ) == .document)
    }

    @Test func normalizesCaseAndOneTrailingDNSDot() {
        #expect(ApplicationContextClassifier().classify(
            bundleIdentifier: "com.google.Chrome",
            applicationName: "Chrome",
            activeBrowserURL: URL(string: "https://MAIL.GOOGLE.COM./mail"),
            browserDomainDetectionAllowed: true
        ) == .email)
    }
}
