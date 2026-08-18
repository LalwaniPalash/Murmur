import Testing

@testable import MurmurNext

@Suite
struct TranscriptionWarmupPolicyTests {
    /// Warmup now runs speculatively in the background at launch, before onboarding has
    /// necessarily installed a model. `lastError` feeds the Flow Bar's message, so a
    /// missing model or absent runtime must not be reported there — the user has not
    /// started a dictation and there is nothing for them to act on yet.
    @Test func absentModelAndRuntimeAreNotReportedAsDictationFailures() {
        #expect(AppEnvironment.isExpectedWarmupPrecondition(LocalTranscriptionError.modelUnavailable))
        #expect(AppEnvironment.isExpectedWarmupPrecondition(LocalTranscriptionError.runtimeUnavailable))
    }

    /// A genuine engine fault still has to surface; silencing everything would hide a
    /// broken runtime until the first dictation failed with no explanation.
    @Test func genuineEngineFailuresStillSurface() {
        #expect(
            AppEnvironment.isExpectedWarmupPrecondition(
                LocalTranscriptionError.processFailed(exitCode: 1, message: "boom")
            ) == false
        )
        #expect(AppEnvironment.isExpectedWarmupPrecondition(LocalTranscriptionError.emptyTranscript) == false)
    }
}
