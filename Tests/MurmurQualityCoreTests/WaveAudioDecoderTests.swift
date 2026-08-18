import Foundation
import Testing

@testable import MurmurQualityCore

struct WaveAudioDecoderTests {
    @Test func decodesPCM16AfterUnknownChunks() throws {
        let data = Self.wave(samples: [Int16.min, 0, Int16.max], includeJunk: true)

        let decoded = try WaveAudioDecoder.decode(data)

        #expect(decoded.sampleRate == 16_000)
        #expect(decoded.samples.count == 3)
        #expect(decoded.samples[0] == -1)
        #expect(decoded.samples[1] == 0)
        #expect(decoded.samples[2] > 0.99)
    }

    @Test func rejectsHeaderOnlyAndStereoFixtures() {
        #expect(throws: WaveAudioDecoderError.invalidContainer) {
            try WaveAudioDecoder.decode(Data("not wave audio".utf8))
        }
        #expect(throws: WaveAudioDecoderError.unsupportedFormat(
            audioFormat: 1,
            channels: 2,
            bitsPerSample: 16
        )) {
            try WaveAudioDecoder.decode(Self.wave(samples: [0], channels: 2))
        }
    }

    private static func wave(
        samples: [Int16],
        channels: UInt16 = 1,
        includeJunk: Bool = false
    ) -> Data {
        var chunks = Data()
        if includeJunk {
            appendASCII("JUNK", to: &chunks)
            append(UInt32(3), to: &chunks)
            chunks.append(contentsOf: [1, 2, 3, 0])
        }
        appendASCII("fmt ", to: &chunks)
        append(UInt32(16), to: &chunks)
        append(UInt16(1), to: &chunks)
        append(channels, to: &chunks)
        append(UInt32(16_000), to: &chunks)
        append(UInt32(16_000 * UInt32(channels) * 2), to: &chunks)
        append(UInt16(channels * 2), to: &chunks)
        append(UInt16(16), to: &chunks)
        appendASCII("data", to: &chunks)
        append(UInt32(samples.count * 2), to: &chunks)
        for sample in samples { append(UInt16(bitPattern: sample), to: &chunks) }

        var result = Data()
        appendASCII("RIFF", to: &result)
        append(UInt32(4 + chunks.count), to: &result)
        appendASCII("WAVE", to: &result)
        result.append(chunks)
        return result
    }

    private static func appendASCII(_ value: String, to data: inout Data) {
        data.append(contentsOf: value.utf8)
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
