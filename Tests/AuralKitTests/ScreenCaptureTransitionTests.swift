import AVFoundation
import Speech
import Testing
@testable import AuralKit

@Suite("Screen capture transitions")
struct ScreenCaptureTransitionTests {
    @Test("Cancellation removes a readiness waiter")
    @MainActor
    func readinessCancellation() async throws {
        try await withCaptureFixture { fixture in
            let gate = fixture.gate()
            let entered = fixture.gate()
            let wait = fixture.track(Task { @MainActor in
                entered.open()
                try await gate.wait()
            })
            try await entered.wait()
            wait.cancel()
            do {
                try await wait.value
                Issue.record("Cancelled wait returned successfully")
            } catch is CancellationError {} // Expected, including cancellation before registration.
            #expect(gate.waiterCount == 0)
        }
    }

    @Test("A missing readiness signal expires and removes its waiter")
    @MainActor
    func readinessDeadline() async throws {
        try await withCaptureFixture { fixture in
            let gate = fixture.gate()
            do {
                try await gate.wait(timeoutNanoseconds: 1_000_000)
                Issue.record("Unopened gate returned successfully")
            } catch CaptureFixtureError.deadline {}
            #expect(gate.waiterCount == 0)
        }
    }

    @Test("A picker replacement stopped across pause never starts the new stream")
    @MainActor
    func replacementHonorsAdmittedPause() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let owner = ScreenCaptureTransitions()
            let old = ControlledCaptureStream()
            let replacement = ControlledCaptureStream()
            let entered = fixture.gate(), release = fixture.gate()
            try await fixture.track(owner.replace { old }).value
            old.stopEntered = entered; old.stopRelease = release
            let update = fixture.track(owner.replace { replacement })
            try await entered.wait()
            let pause = fixture.track(owner.pause())
            #expect(owner.desiredState == .paused)
            release.open()
            try await update.value
            try await pause.value
            #expect(owner.stream === replacement)
            #expect(!owner.isRunning)
            #expect(!old.capturing)
            #expect(replacement.starts == 0)
            let resumed = await fixture.track(owner.resume()).value
            #expect(resumed.isCurrent())
            #expect(resumed.error == nil)
            #expect(replacement.starts == 1)
            #expect(old.starts == 1)
            try await fixture.track(owner.stop()).value
        }
    }

    @Test("Stop admitted during old shutdown prevents either replacement from starting")
    @MainActor
    func replacementIdentityAcrossStop() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let owner = ScreenCaptureTransitions()
            let old = ControlledCaptureStream()
            let obsolete = ControlledCaptureStream(), current = ControlledCaptureStream()
            let entered = fixture.gate(), release = fixture.gate()
            try await fixture.track(owner.replace { old }).value
            old.stopEntered = entered; old.stopRelease = release
            let first = fixture.track(owner.replace { obsolete })
            try await entered.wait()
            let second = fixture.track(owner.replace { current })
            let stop = fixture.track(owner.stop())
            #expect(obsolete.starts == 0 && current.starts == 0)
            release.open()
            try await first.value
            try await second.value
            try await stop.value
            #expect(owner.stream == nil)
            #expect(!old.capturing)
            #expect(obsolete.starts == 0 && current.starts == 0)
        }
    }

    @Test("A superseded start compensates before its successor can start")
    @MainActor
    func replacementIdentityAcrossStart() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let owner = ScreenCaptureTransitions()
            let obsolete = ControlledCaptureStream(), current = ControlledCaptureStream()
            let startEntered = fixture.gate(), startRelease = fixture.gate()
            let stopEntered = fixture.gate(), stopRelease = fixture.gate()
            obsolete.startEntered = startEntered; obsolete.startRelease = startRelease
            obsolete.stopEntered = stopEntered; obsolete.stopRelease = stopRelease
            let first = fixture.track(owner.replace { obsolete })
            try await startEntered.wait()
            let second = fixture.track(owner.replace { current })
            startRelease.open()
            try await stopEntered.wait()
            #expect(current.starts == 0)
            #expect(owner.stream === obsolete)
            stopRelease.open()
            try await first.value
            try await second.value
            #expect(!obsolete.capturing)
            #expect(obsolete.stops == 1)
            #expect(owner.stream === current)
            #expect(current.starts == 1)
            try await fixture.track(owner.stop()).value
        }
    }
}

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit

/// Replaces only authorization, native analyzer preparation/finalization and picker
/// presentation. Public setup, provider, picker admission, transitions and stop are real.
@available(iOS 27.0, macOS 26.0, *)
@MainActor
private final class PublicCaptureFixture {
    let session = SpeechSession()
    let owner = ScreenCaptureTransitions()
    let stream = ControlledCaptureStream()
    var provider: ScreenCaptureAudioInputProvider?
    let presented: CaptureGate
    let dismissed: CaptureGate
    let finalized: CaptureGate
    let finalizeRelease: CaptureGate
    let terminal: CaptureGate
    var consumerFinished = false
    var consumerError: Error?

    init(_ fixture: CaptureFixture) {
        presented = fixture.gate(); dismissed = fixture.gate()
        finalized = fixture.gate(); finalizeRelease = fixture.gate(); terminal = fixture.gate()
        session.screenCapturePipelineHooks = ScreenCapturePipelineHooks(
            authorize: {},
            prepareAnalysis: { [self] in
                let (_, inputs) = AsyncStream<AnalyzerInput>.makeStream()
                return ScreenCapturePreparedAnalysis(
                    format: AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!,
                    inputs: inputs,
                    finalize: { [self] in
                        finalized.open()
                        // A native call may ignore the cancelling caller until explicitly released.
                        let join = fixture.track(Task { @MainActor in try await finalizeRelease.wait() })
                        do { try await join.value } catch { Issue.record("Finalization gate failed: \(error)") }
                    }
                )
            },
            makeProvider: { [self] format, inputs, failure in
                let provider = ScreenCaptureAudioInputProvider(
                    options: .init(), targetFormat: format, inputContinuation: inputs,
                    onFailure: failure, transitions: owner,
                    presentPicker: { [self] _ in presented.open() },
                    dismissPicker: { [self] _ in dismissed.open() }
                )
                self.provider = provider
                return provider
            }
        )
    }

    func start(_ fixture: CaptureFixture, select: Bool = true) async throws {
        let results = session.startTranscribingScreenCapture()
        fixture.track(Task { @MainActor in
            do { for try await _ in results {} } catch { consumerError = error }
            consumerFinished = true
            terminal.open()
        })
        try await presented.wait()
        if select {
            provider?.selectStream { [self] in stream }
            // Public pause waits until setup has published transcribing. Readiness is
            // observed from the existing status stream, never a state setter or a delay.
            let ready = fixture.gate()
            let statuses = session.statusStream
            fixture.track(Task { @MainActor in
                for await status in statuses where status == .transcribing {
                    ready.open()
                    return
                }
            })
            try await ready.wait()
        }
    }

    func close(_ fixture: CaptureFixture) async {
        fixture.releaseAll()
        await fixture.track(Task { await session.stopTranscribing() }).value
        session.screenCapturePipelineHooks = nil
    }
}

extension ScreenCaptureTransitionTests {
    @Test(
        "Public stop joins pending setup or resume and concurrent stop through finalization",
        arguments: [false, true]
    )
    @MainActor
    func publicStopJoinsSetupUnwindAndConcurrentStop(afterPause: Bool) async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = PublicCaptureFixture(fixture)
            do {
                // Pending initial selection wakes the real setup catch on stop. The
                // second case enters public resume after a real public start and pause.
                try await runtime.start(fixture, select: afterPause)
                if afterPause { await runtime.session.pauseTranscribing() }
                let entered = fixture.gate(), release = fixture.gate()
                runtime.stream.startEntered = entered; runtime.stream.startRelease = release
                var resume: Task<Void, Error>?
                if afterPause {
                    resume = fixture.track(Task { try await runtime.session.resumeTranscribing() })
                } else {
                    runtime.provider?.selectStream { runtime.stream }
                }
                try await entered.wait()
                var firstReturned = false, secondReturned = false
                let first = fixture.track(Task { @MainActor in
                    await runtime.session.stopTranscribing(); firstReturned = true
                })
                try await runtime.dismissed.wait()
                let secondEntered = fixture.gate()
                let second = fixture.track(Task { @MainActor in
                    secondEntered.open()
                    await runtime.session.stopTranscribing(); secondReturned = true
                })
                try await secondEntered.wait()
                #expect(!firstReturned && !secondReturned)
                #expect(!runtime.consumerFinished)
                #expect(runtime.session.status != .idle)
                release.open()
                try await runtime.finalized.wait()
                #expect(!runtime.stream.capturing)
                #expect(!firstReturned && !secondReturned)
                #expect(!runtime.consumerFinished)
                runtime.finalizeRelease.open()
                await first.value; await second.value
                try await resume?.value
                try await runtime.terminal.wait()
                #expect(firstReturned && secondReturned)
                #expect(runtime.session.status == .idle)
                #expect(runtime.consumerError == nil)
            } catch {
                await runtime.close(fixture)
                throw error
            }
            await runtime.close(fixture)
        }
    }

    @Test("Late failing public resume cannot retire a newer picker admission")
    @MainActor
    func supersededPublicResumeFailure() async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = PublicCaptureFixture(fixture)
            do {
                try await runtime.start(fixture)
                await runtime.session.pauseTranscribing()
                #expect(runtime.session.status == .paused)
                let entered = fixture.gate(), release = fixture.gate()
                runtime.stream.startEntered = entered; runtime.stream.startRelease = release
                runtime.stream.startError = CaptureFixtureError.startFailed
                let resume = fixture.track(Task { try await runtime.session.resumeTranscribing() })
                try await entered.wait()
                let successor = ControlledCaptureStream()
                let successorStarted = fixture.gate()
                successor.startEntered = successorStarted
                runtime.provider?.selectStream { successor }
                release.open()
                try await resume.value
                try await successorStarted.wait()
                #expect(!runtime.consumerFinished)
                #expect(runtime.session.status == .transcribing)
                #expect(runtime.owner.stream === successor)
                #expect(successor.capturing)
                await runtime.session.pauseTranscribing()
                #expect(!successor.capturing)
                successor.startError = CaptureFixtureError.startFailed
                runtime.finalizeRelease.open()
                do {
                    try await runtime.session.resumeTranscribing()
                    Issue.record("Current resume failure was lost")
                } catch CaptureFixtureError.startFailed {} // Original error must propagate.
                try await runtime.terminal.wait()
                #expect(runtime.consumerError is CaptureFixtureError)
            } catch {
                await runtime.close(fixture)
                throw error
            }
            await runtime.close(fixture)
        }
    }
}
#endif
