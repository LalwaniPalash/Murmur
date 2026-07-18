import Testing
@testable import MurmurNext

struct ApplicationContextClassifierTests {
    @Test(arguments: [
        ("com.tinyspeck.slackmacgap", "Slack", WritingContext.messaging),
        ("com.apple.mail", "Mail", WritingContext.email),
        ("com.microsoft.Word", "Microsoft Word", WritingContext.document),
        ("company.thebrowser.Browser", "Arc", WritingContext.browser),
        ("com.todesktop.230313mzl4w4u92", "Cursor", WritingContext.code),
        ("com.googlecode.iterm2", "iTerm2", WritingContext.terminal),
        ("com.example.unknown", "Something", WritingContext.general),
    ])
    func classifiesKnownWritingApplications(bundleID: String, name: String, expected: WritingContext) {
        #expect(ApplicationContextClassifier().classify(bundleIdentifier: bundleID, applicationName: name) == expected)
    }
}
