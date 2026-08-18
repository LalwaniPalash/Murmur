import AVFoundation
import Foundation

@MainActor
protocol RetainedAudioOutputServicing: AnyObject {
    func play(samples: [Float], sampleRate: Int) throws
    func stop()
}

@MainActor
final class SystemRetainedAudioOutput: RetainedAudioOutputServicing {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isAttached = false
    private var connectedSampleRate: Double?

    func play(samples: [Float], sampleRate: Int) throws {
        guard samples.isEmpty == false,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(sampleRate),
                channels: 1,
                interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = buffer.floatChannelData?[0]
        else { throw EncryptedAudioVaultError.invalidFormat }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        channel.update(from: samples, count: samples.count)

        if isAttached == false {
            engine.attach(player)
            isAttached = true
        }
        if connectedSampleRate != format.sampleRate {
            player.stop()
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            connectedSampleRate = format.sampleRate
        }
        if engine.isRunning == false {
            engine.prepare()
            try engine.start()
        }
        player.stop()
        player.scheduleBuffer(buffer)
        player.play()
    }

    func stop() {
        player.stop()
        engine.stop()
    }
}

@MainActor
final class RetainedAudioPlayback {
    private let retention: RetentionCoordinator
    private let output: any RetainedAudioOutputServicing

    init(
        retention: RetentionCoordinator,
        output: any RetainedAudioOutputServicing = SystemRetainedAudioOutput()
    ) {
        self.retention = retention
        self.output = output
    }

    func play(sessionID: UUID) async throws {
        let retained = try await retention.samples(sessionID: sessionID)
        try output.play(samples: retained.samples, sampleRate: retained.sampleRate)
    }

    func stop() { output.stop() }
}
