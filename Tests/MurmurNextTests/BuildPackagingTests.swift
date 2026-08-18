import Foundation
import Testing

struct BuildPackagingTests {
    @Test func packagedAppRejectsConcurrentInstances() throws {
        var projectRoot = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { projectRoot.deleteLastPathComponent() }
        let scriptURL = projectRoot.appendingPathComponent("script/build_and_run.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(script.contains("<key>LSMultipleInstancesProhibited</key>\n  <true/>"))
        #expect(script.contains("/usr/bin/open -n") == false)
        #expect(script.contains("APP_HELPERS=\"$APP_CONTENTS/Helpers\""))
        #expect(script.contains("MurmurMLXWorker"))
        #expect(script.contains("Missing MLX worker build product"))
        #expect(script.contains("mlx.metallib"))
        #expect(script.contains("Missing pinned MLX Metal library"))
    }
}
