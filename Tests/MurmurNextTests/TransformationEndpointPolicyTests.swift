import Foundation
import Testing
@testable import MurmurNext

struct TransformationEndpointPolicyTests {
    @Test(arguments: [
        "https://api.openai.com/v1",
        "https://writer.example.test:8443/api",
        "http://localhost:11434/v1",
        "http://127.0.0.1:1234/v1",
        "http://[::1]:8080/v1",
    ])
    func acceptsHTTPSAndHTTPOnlyOnLoopback(value: String) throws {
        let url = try TransformationEndpointPolicy.validate(value)
        #expect(url.absoluteString.hasSuffix("/") == false)
    }

    @Test(arguments: [
        "http://api.openai.com/v1",
        "http://localhost.evil.test/v1",
        "ftp://localhost/model",
        "https://user:password@example.com/v1",
        "https://example.com/v1#secret",
        "https:///missing-host",
    ])
    func rejectsUnsafeOrAmbiguousEndpoints(value: String) {
        #expect(throws: TransformationEndpointError.self) {
            try TransformationEndpointPolicy.validate(value)
        }
    }

    @Test func appendsOneAPIRouteWithoutDuplicatingVersionPath() throws {
        let base = try TransformationEndpointPolicy.validate("https://writer.example.test/v1/")
        #expect(try TransformationEndpointPolicy.endpoint(base: base, route: "responses").absoluteString == "https://writer.example.test/v1/responses")

        let root = try TransformationEndpointPolicy.validate("https://writer.example.test")
        #expect(try TransformationEndpointPolicy.endpoint(base: root, route: "/v1/responses").absoluteString == "https://writer.example.test/v1/responses")
    }
}
