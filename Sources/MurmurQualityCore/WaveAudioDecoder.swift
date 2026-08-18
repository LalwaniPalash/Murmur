import Foundation

public struct DecodedWaveAudio: Equatable, Sendable {
    public let samples: [Float]
    public let sampleRate: UInt32

    public init(samples: [Float], sampleRate: UInt32) {
        self.samples = samples
        self.sampleRate = sampleRate
    }
}

public enum WaveAudioDecoderError: Error, LocalizedError, Equatable, Sendable {
    case invalidContainer
    case missingFormat
    case missingAudioData
    case unsupportedFormat(audioFormat: UInt16, channels: UInt16, bitsPerSample: UInt16)
    case truncatedChunk

    public var errorDescription: String? {
        switch self {
        case .invalidContainer:
            "The fixture is not a RIFF/WAVE file."
        case .missingFormat:
            "The WAVE fixture has no format chunk."
        case .missingAudioData:
            "The WAVE fixture has no audio data chunk."
        case .unsupportedFormat(let audioFormat, let channels, let bitsPerSample):
            "Only mono PCM16 WAVE fixtures are supported (format \(audioFormat), channels \(channels), bits \(bitsPerSample))."
        case .truncatedChunk:
            "The WAVE fixture contains a truncated chunk."
        }
    }
}

public enum WaveAudioDecoder {
    public static func decode(contentsOf url: URL) throws -> DecodedWaveAudio {
        try decode(Data(contentsOf: url, options: [.mappedIfSafe]))
    }

    public static func decode(_ data: Data) throws -> DecodedWaveAudio {
        guard data.count >= 12,
              ascii(data, at: 0, count: 4) == "RIFF",
              ascii(data, at: 8, count: 4) == "WAVE"
        else { throw WaveAudioDecoderError.invalidContainer }

        var format: (audioFormat: UInt16, channels: UInt16, sampleRate: UInt32, bitsPerSample: UInt16)?
        var audioBytes: Data?
        var offset = 12
        while offset + 8 <= data.count {
            let identifier = ascii(data, at: offset, count: 4)
            let size = Int(readUInt32(data, at: offset + 4))
            let payloadStart = offset + 8
            guard size >= 0, payloadStart <= data.count, size <= data.count - payloadStart else {
                throw WaveAudioDecoderError.truncatedChunk
            }
            let payloadEnd = payloadStart + size
            switch identifier {
            case "fmt ":
                guard size >= 16 else { throw WaveAudioDecoderError.truncatedChunk }
                format = (
                    readUInt16(data, at: payloadStart),
                    readUInt16(data, at: payloadStart + 2),
                    readUInt32(data, at: payloadStart + 4),
                    readUInt16(data, at: payloadStart + 14)
                )
            case "data":
                audioBytes = data.subdata(in: payloadStart..<payloadEnd)
            default:
                break
            }
            offset = payloadEnd + (size.isMultiple(of: 2) ? 0 : 1)
        }

        guard let format else { throw WaveAudioDecoderError.missingFormat }
        guard format.audioFormat == 1, format.channels == 1, format.bitsPerSample == 16 else {
            throw WaveAudioDecoderError.unsupportedFormat(
                audioFormat: format.audioFormat,
                channels: format.channels,
                bitsPerSample: format.bitsPerSample
            )
        }
        guard let audioBytes else { throw WaveAudioDecoderError.missingAudioData }
        guard audioBytes.count.isMultiple(of: 2) else { throw WaveAudioDecoderError.truncatedChunk }

        var samples: [Float] = []
        samples.reserveCapacity(audioBytes.count / 2)
        var sampleOffset = 0
        while sampleOffset < audioBytes.count {
            let value = Int16(bitPattern: readUInt16(audioBytes, at: sampleOffset))
            samples.append(Float(value) / 32_768)
            sampleOffset += 2
        }
        return DecodedWaveAudio(samples: samples, sampleRate: format.sampleRate)
    }

    private static func ascii(_ data: Data, at offset: Int, count: Int) -> String? {
        guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else { return nil }
        return String(data: data.subdata(in: offset..<(offset + count)), encoding: .ascii)
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
