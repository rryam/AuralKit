#if canImport(ScreenCaptureKit)
import AVFoundation
import Speech
import Testing
@testable import AuralKit

@available(iOS 27.0, macOS 26.0, *)
@MainActor
final class CaptureSessionFixture {
    let session = SpeechSession()
    let owner = ScreenCaptureTransitions()
    let provider: ScreenCaptureAudioInputProvider
    let dismissed: CaptureGate

    init(_ fixture: CaptureFixture, terminationRelease: CaptureGate? = nil) throws {
        dismissed = fixture.gate()
        let (_, inputs) = AsyncStream<AnalyzerInput>.makeStream()
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let generation = session.sessionGeneration
        provider = ScreenCaptureAudioInputProvider(
            options: .init(), targetFormat: format, inputContinuation: inputs,
            onTermination: { [session] error in
                Task { @MainActor in
                    try? await terminationRelease?.wait()
                    await session.finishFromRecognizerTask(error: error, generation: generation)
                }
            }, transitions: owner,
            dismissPicker: { [dismissed] _ in dismissed.open() }
        )
        session.screenCaptureInputProvider = provider
        session.streamingMode = .screenCapture
        session.setStatus(.transcribing)
    }

    func close(_ fixture: CaptureFixture) async {
        fixture.releaseAll()
        await session.cancelTranscribing()
    }
}

@Suite("Screen capture transitions")
struct ScreenCaptureTransitionTests {
    @Test("Replacing a pending picker start stops it before starting its successor")
    @MainActor
    func replacementDuringStart() async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = try CaptureSessionFixture(fixture)
            let old = ControlledCaptureStream(), successor = ControlledCaptureStream()
            let entered = fixture.gate(), release = fixture.gate()
            let stopping = fixture.gate(), stopped = fixture.gate()
            old.startEntered = entered; old.startRelease = release
            old.stopEntered = stopping; old.stopRelease = stopped
            let first = fixture.track(runtime.provider.selectStream { old })
            try await entered.wait()
            let second = fixture.track(runtime.provider.selectStream { successor })
            release.open()
            try await stopping.wait()
            #expect(old.capturing && successor.starts == 0)
            stopped.open()
            await first.value; await second.value
            #expect(!old.capturing && old.stops == 1)
            #expect(successor.capturing && successor.starts == 1)
            await runtime.close(fixture)
        }
    }

    @Test("Public pause during replacement prevents queued selections from starting")
    @MainActor
    func pauseDuringReplacement() async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = try CaptureSessionFixture(fixture)
            let old = ControlledCaptureStream(), replacement = ControlledCaptureStream()
            let latest = ControlledCaptureStream()
            await fixture.track(runtime.provider.selectStream { old }).value
            let entered = fixture.gate(), release = fixture.gate()
            old.stopEntered = entered; old.stopRelease = release
            let first = fixture.track(runtime.provider.selectStream { replacement })
            try await entered.wait()
            let pause = fixture.track(Task { await runtime.session.pauseTranscribing() })
            try await waitForCaptureState { runtime.owner.desiredState == .paused }
            let second = fixture.track(runtime.provider.selectStream { latest })
            release.open()
            await first.value; await second.value; await pause.value
            #expect(runtime.session.status == .paused)
            #expect(!old.capturing && replacement.starts == 0 && latest.starts == 0)
            try await runtime.session.resumeTranscribing()
            #expect(latest.capturing && runtime.session.status == .transcribing)
            await runtime.close(fixture)
        }
    }

    @Test("Finish drains screen input unless Cancel supersedes it", arguments: [false, true])
    @MainActor
    func finishDrainsScreenSource(cancel: Bool) async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = try CaptureSessionFixture(fixture)
            let source = ControlledCaptureStream()
            await fixture.track(runtime.provider.selectStream { source }).value

            let stopEntered = fixture.gate(), stopRelease = fixture.gate()
            source.stopEntered = stopEntered
            source.stopRelease = stopRelease
            let (inputs, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
            runtime.session.inputBuilder = inputBuilder
            let (results, resultContinuation) = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()
            runtime.session.continuation = .speech(resultContinuation)
            let generation = runtime.session.sessionGeneration
            let resultsTask = Task {
                for await _ in inputs {}
                await runtime.session.finishFromRecognizerTask(error: nil, generation: generation)
            }
            defer { resultsTask.cancel() }
            runtime.session.recognizerTask = resultsTask
            let finish = fixture.track(Task { await runtime.session.finishTranscribing() })
            try await stopEntered.wait()
            #expect(runtime.session.status == .stopping)
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
            let pcm = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
            pcm.frameLength = 1
            let input = AnalyzerInput(buffer: pcm)
            if case .terminated = inputBuilder.yield(input) {
                Issue.record("The input stream closed before the screen source stopped")
            }
            if cancel {
                let cancelTask = fixture.track(Task { await runtime.session.cancelTranscribing() })
                try await waitForCaptureState { runtime.session.inputBuilder == nil }
                switch inputBuilder.yield(input) {
                case .terminated: break
                default: Issue.record("Cancel left the input stream open")
                }
                stopRelease.open()
                await cancelTask.value
                await #expect(throws: CancellationError.self) {
                    for try await _ in results {}
                }
            } else {
                stopRelease.open()
                var iterator = results.makeAsyncIterator()
                let result = try await iterator.next()
                #expect(result == nil)
            }
            await finish.value
            #expect(runtime.session.status == .idle)
        }
    }

    @Test("Concurrent public stops join a replacement start and its compensating stop")
    @MainActor
    func stopDuringReplacementStart() async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = try CaptureSessionFixture(fixture)
            let previous = ControlledCaptureStream()
            await fixture.track(runtime.provider.selectStream { previous }).value
            let stream = ControlledCaptureStream()
            let entered = fixture.gate(), release = fixture.gate()
            let stopping = fixture.gate(), stopped = fixture.gate()
            stream.startEntered = entered; stream.startRelease = release
            stream.stopEntered = stopping; stream.stopRelease = stopped
            let selection = fixture.track(runtime.provider.selectStream { stream })
            try await entered.wait()
            var firstReturned = false, secondReturned = false
            let first = fixture.track(Task {
                await runtime.session.cancelTranscribing(); firstReturned = true
            })
            try await runtime.dismissed.wait()
            let secondEntered = fixture.gate()
            let second = fixture.track(Task {
                secondEntered.open()
                await runtime.session.cancelTranscribing(); secondReturned = true
            })
            try await secondEntered.wait()
            #expect(!firstReturned && !secondReturned)
            release.open()
            try await stopping.wait()
            #expect(!firstReturned && !secondReturned)
            #expect(runtime.session.status == .stopping)
            stopped.open()
            await first.value; await second.value; await selection.value
            #expect(firstReturned && secondReturned)
            #expect(!previous.capturing && !stream.capturing && runtime.owner.stream == nil)
            #expect(runtime.session.status == .idle)
        }
    }

    @Test("Superseded public resume publishes running and allows pause", arguments: [false, true])
    @MainActor
    func supersededPublicResumeFailure(fails: Bool) async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = try CaptureSessionFixture(fixture)
            let old = ControlledCaptureStream(), successor = ControlledCaptureStream()
            await fixture.track(runtime.provider.selectStream { old }).value
            await runtime.session.pauseTranscribing()
            let entered = fixture.gate(), release = fixture.gate()
            old.startEntered = entered; old.startRelease = release
            old.startError = fails ? CaptureFixtureError.startFailed : nil
            var resumeReturned = false
            let resume = fixture.track(Task {
                try await runtime.session.resumeTranscribing(); resumeReturned = true
            })
            try await entered.wait()
            let successorEntered = fixture.gate(), successorRelease = fixture.gate()
            successor.startEntered = successorEntered; successor.startRelease = successorRelease
            let replacement = fixture.track(runtime.provider.selectStream { successor })
            release.open()
            try await successorEntered.wait()
            #expect(!resumeReturned && runtime.session.status == .paused)
            successorRelease.open()
            try await resume.value
            await replacement.value
            #expect(runtime.session.status == .transcribing && successor.capturing)
            #expect(!old.capturing)
            await runtime.session.pauseTranscribing()
            #expect(runtime.session.status == .paused && !successor.capturing)
            #expect(successor.stops == 1)
            await runtime.close(fixture)
        }
    }

    @Test("Current resume failure still propagates and tears down")
    @MainActor
    func currentResumeFailure() async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = try CaptureSessionFixture(fixture)
            let stream = ControlledCaptureStream()
            await fixture.track(runtime.provider.selectStream { stream }).value
            await runtime.session.pauseTranscribing()
            stream.startError = CaptureFixtureError.startFailed
            await #expect(throws: CaptureFixtureError.self) {
                try await runtime.session.resumeTranscribing()
            }
            #expect(runtime.session.status == .idle && !stream.capturing)
        }
    }

    @Test("A failed native pause keeps the public status transcribing", arguments: [false, true])
    @MainActor
    func failedPause(replaceAfterFailure: Bool) async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = try CaptureSessionFixture(fixture)
            let stream = ControlledCaptureStream()
            await fixture.track(runtime.provider.selectStream { stream }).value
            stream.stopError = CaptureFixtureError.startFailed
            await runtime.session.pauseTranscribing()
            #expect(runtime.session.status == .transcribing && stream.capturing)
            stream.stopError = nil
            let active = replaceAfterFailure ? ControlledCaptureStream() : stream
            if replaceAfterFailure {
                await fixture.track(runtime.provider.selectStream { active }).value
                #expect(active.capturing && runtime.session.status == .transcribing)
            }
            await runtime.session.pauseTranscribing()
            #expect(runtime.session.status == .paused && !active.capturing && !stream.capturing)
            await runtime.close(fixture)
        }
    }
}
#endif
