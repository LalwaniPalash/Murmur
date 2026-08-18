import Testing
@testable import MurmurNext

struct GlobalShortcutMonitorTests {
    @Test func controlBeforeFnStartsCommandDirectly() {
        var resolver = ShortcutChordResolver()

        #expect(resolver.observe(
            functionIsDown: false,
            controlIsDown: true,
            nowNanoseconds: 1
        ).isEmpty)
        #expect(resolver.observe(
            functionIsDown: true,
            controlIsDown: true,
            nowNanoseconds: 2
        ) == [.beginCommand])
        #expect(resolver.observe(
            functionIsDown: false,
            controlIsDown: true,
            nowNanoseconds: 3
        ) == [.endCommand])
    }

    @Test func fnBeforeControlUpgradesTheSameCaptureToCommand() {
        var resolver = ShortcutChordResolver()

        #expect(resolver.observe(
            functionIsDown: true,
            controlIsDown: false,
            nowNanoseconds: 1_000_000_000
        ) == [.beginDictation])
        #expect(resolver.observe(
            functionIsDown: true,
            controlIsDown: true,
            nowNanoseconds: 1_020_000_000
        ) == [.requestCommandUpgrade])

        resolver.confirmCommandUpgrade()
        #expect(resolver.observe(
            functionIsDown: false,
            controlIsDown: true,
            nowNanoseconds: 1_030_000_000
        ) == [.endCommand])
    }

    @Test func fnThenControlAfterHumanDelayStillRequestsCommandUpgrade() {
        var resolver = ShortcutChordResolver()

        #expect(resolver.observe(
            functionIsDown: true,
            controlIsDown: false,
            nowNanoseconds: 1_000_000_000
        ) == [.beginDictation])
        #expect(resolver.observe(
            functionIsDown: true,
            controlIsDown: true,
            nowNanoseconds: 1_750_000_000
        ) == [.requestCommandUpgrade])
        resolver.confirmCommandUpgrade()
        #expect(resolver.observe(
            functionIsDown: false,
            controlIsDown: true,
            nowNanoseconds: 1_760_000_000
        ) == [.endCommand])
    }
}
