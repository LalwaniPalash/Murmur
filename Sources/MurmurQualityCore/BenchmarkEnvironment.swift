import Darwin
import Foundation

public enum BenchmarkEnvironment {
    public static var hardwareIdentifier: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else {
            return "unknown-mac"
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else {
            return "unknown-mac"
        }
        let utf8 = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: utf8, as: UTF8.self)
    }

    public static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return (Double(components.seconds) * 1_000)
            + (Double(components.attoseconds) / 1_000_000_000_000_000)
    }
}
