#if canImport(ScreenCaptureKit)
import AVFoundation
import Speech
import Testing
@testable import AuralKit

@Suite("Finishing screen transcription")
struct ScreenCaptureFinishTests {
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
            let input = try makeAnalyzerInput()
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

    @Test("Finish reports a native screen stop failure")
    @MainActor
    func finishReportsScreenStopFailure() async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = try CaptureSessionFixture(fixture)
            let source = ControlledCaptureStream()
            await fixture.track(runtime.provider.selectStream { source }).value
            source.stopError = CaptureFixtureError.startFailed
            let (results, continuation) = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()
            runtime.session.continuation = .speech(continuation)
            runtime.session.recognizerTask = Task { try? await Task.sleep(for: .seconds(10)) }

            await runtime.session.finishTranscribing()

            await #expect(throws: CaptureFixtureError.self) {
                for try await _ in results {}
            }
            #expect(runtime.session.status == .idle)
        }
    }

    @Test("A delegate failure during native stop reaches Finish unless Cancel wins", arguments: [false, true])
    @MainActor
    func delegateErrorDuringFinish(cancel: Bool) async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = try CaptureSessionFixture(fixture)
            let source = ControlledCaptureStream()
            await fixture.track(runtime.provider.selectStream { source }).value
            let stopEntered = fixture.gate(), stopRelease = fixture.gate()
            source.stopEntered = stopEntered
            source.stopRelease = stopRelease
            source.stopError = CaptureFixtureError.deadline
            let (results, continuation) = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()
            runtime.session.continuation = .speech(continuation)
            runtime.session.recognizerTask = Task { try? await Task.sleep(for: .seconds(10)) }

            let finish = fixture.track(Task { await runtime.session.finishTranscribing() })
            try await stopEntered.wait()
            runtime.provider.streamDidStop(source, error: CaptureFixtureError.startFailed)
            if cancel {
                fixture.track(Task { await runtime.session.cancelTranscribing() })
                try await waitForCaptureState { runtime.session.cancellationRequested }
            }
            stopRelease.open()
            await finish.value

            do {
                for try await _ in results {}
                Issue.record("Expected terminal failure")
            } catch is CancellationError {
                #expect(cancel)
            } catch SpeechSessionError.screenCaptureFailed(let underlyingError) {
                #expect(!cancel)
                #expect(underlyingError as? CaptureFixtureError == .startFailed)
            }
            #expect(source.stops == 1)
            #expect(runtime.session.status == .idle)
        }
    }

    @Test("Cancel wins while the successful screen completion still owns cleanup")
    @MainActor
    func cancelDuringTerminalScreenCleanup() async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = try CaptureSessionFixture(fixture)
            let source = ControlledCaptureStream()
            await fixture.track(runtime.provider.selectStream { source }).value
            let stopEntered = fixture.gate(), stopRelease = fixture.gate()
            source.stopEntered = stopEntered
            source.stopRelease = stopRelease

            let (results, continuation) = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()
            runtime.session.continuation = .speech(continuation)
            let generation = runtime.session.sessionGeneration
            let completed = fixture.track(Task {
                await runtime.session.finishFromRecognizerTask(error: nil, generation: generation)
            })
            try await stopEntered.wait()
            let cancel = fixture.track(Task { await runtime.session.cancelTranscribing() })
            try await waitForCaptureState { runtime.session.cancellationRequested }
            stopRelease.open()
            await cancel.value
            await completed.value

            await #expect(throws: CancellationError.self) {
                for try await _ in results {}
            }
            #expect(source.stops == 1)
            #expect(runtime.session.status == .idle)
        }
    }

    private func makeAnalyzerInput() throws -> AnalyzerInput {
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true
        ))
        let pcm = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
        pcm.frameLength = 160
        pcm.int16ChannelData?.pointee.initialize(repeating: 0, count: 160)
        return AnalyzerInput(buffer: pcm)
    }
}
#endif
