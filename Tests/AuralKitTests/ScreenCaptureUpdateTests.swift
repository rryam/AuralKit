#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
import Speech
import Testing
@testable import AuralKit

@Suite("Screen capture updates and termination")
struct ScreenCaptureUpdateTests {
    @Test("Terminal errors reach a pending resume unless explicit stop won", arguments: [false, true])
    @MainActor
    func terminalErrorDuringResume(stopFirst: Bool) async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = try CaptureSessionFixture(fixture)
            let stream = ControlledCaptureStream()
            await fixture.track(runtime.provider.selectStream { stream }).value
            await runtime.session.pauseTranscribing()
            let started = fixture.gate(), release = fixture.gate()
            stream.startEntered = started; stream.startRelease = release
            let resume = fixture.track(Task { try await runtime.session.resumeTranscribing() })
            try await started.wait()
            if stopFirst {
                fixture.track(Task { await runtime.session.stopTranscribing() })
            }
            await fixture.track(Task { @MainActor in
                if stopFirst { #expect(runtime.session.status == .stopping) }
                stream.terminated = true
                runtime.provider.streamDidStop(stream, error: CaptureFixtureError.startFailed)
            }).value
            try await runtime.dismissed.wait()
            release.open()
            try await waitForCaptureState { runtime.session.status == .idle }
            if stopFirst {
                try await resume.value
            } else {
                await #expect(throws: SpeechSessionError.self) { try await resume.value }
            }
            #expect(!runtime.owner.isRunning && stream.stops == 1)
        }
    }

    @Test("Filter updates cannot hide a pending start failure", arguments: [false, true])
    @MainActor
    func updateDuringFailedStart(staleUpdate: Bool) async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = try CaptureSessionFixture(fixture)
            let old = ControlledCaptureStream(), pending = ControlledCaptureStream()
            if staleUpdate { await fixture.track(runtime.provider.selectStream { old }).value }
            let (results, continuation) = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()
            runtime.session.continuation = .speech(continuation)
            let started = fixture.gate(), release = fixture.gate()
            pending.startEntered = started; pending.startRelease = release
            pending.startError = CaptureFixtureError.startFailed
            let selection = fixture.track(runtime.provider.selectStream { pending })
            try await started.wait()
            let update = fixture.track(runtime.provider.updateStream(staleUpdate ? old : pending) {})
            release.open()
            await selection.value; await update.value
            await #expect(throws: SpeechSessionError.self) {
                try await awaitResult(timeout: 1) { for try await _ in results {} }
            }
            #expect(runtime.session.status == .idle && !pending.capturing)
            await runtime.close(fixture)
        }
    }

    @Test("Repeated filter updates retain the selected stream", arguments: [false, true])
    @MainActor
    func repeatedUpdates(paused: Bool) async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = try CaptureSessionFixture(fixture)
            let stream = ControlledCaptureStream()
            await fixture.track(runtime.provider.selectStream { stream }).value
            if paused { await runtime.session.pauseTranscribing() }
            var filters: [Int] = []
            for filter in [1, 2] {
                await fixture.track(runtime.provider.updateStream(stream) { filters.append(filter) }).value
            }
            #expect(filters == [1, 2] && runtime.owner.stream === stream)
            #expect(stream.starts == 1 && stream.stops == (paused ? 1 : 0))
            #expect(stream.capturing == !paused)
            #expect(runtime.session.status == (paused ? .paused : .transcribing))
            if paused { try await runtime.session.resumeTranscribing() }
            let successor = ControlledCaptureStream()
            await fixture.track(runtime.provider.selectStream { successor }).value
            await fixture.track(runtime.provider.updateStream(stream) { filters.append(3) }).value
            runtime.provider.streamDidStop(stream, error: CaptureFixtureError.startFailed)
            #expect(filters == [1, 2] && successor.capturing)
            #expect(runtime.session.status == .transcribing)
            await runtime.close(fixture)
        }
    }

    @Test("Filter updates serialize with pending start and pause or stop", arguments: [false, true])
    @MainActor
    func updateDuringStart(stop: Bool) async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = try CaptureSessionFixture(fixture)
            let stream = ControlledCaptureStream()
            let started = fixture.gate(), startRelease = fixture.gate()
            let updating = fixture.gate(), updateRelease = fixture.gate()
            stream.startEntered = started; stream.startRelease = startRelease
            let selection = fixture.track(runtime.provider.selectStream { stream })
            try await started.wait()
            var updates = 0
            let update = fixture.track(runtime.provider.updateStream(stream) {
                updates += 1; updating.open(); try await updateRelease.wait()
            })
            startRelease.open()
            try await updating.wait()
            #expect(stream.capturing && stream.starts == 1 && stream.stops == 0)
            let control = fixture.track(Task {
                if stop { await runtime.session.stopTranscribing() } else { await runtime.session.pauseTranscribing() }
            })
            try await waitForCaptureState { runtime.owner.desiredState == (stop ? .stopped : .paused) }
            let later = fixture.track(runtime.provider.updateStream(stream) { updates += 1 })
            updateRelease.open()
            await selection.value; await update.value; await control.value; await later.value
            #expect(updates == (stop ? 1 : 2))
            #expect(!stream.capturing && stream.stops == 1)
            #expect(runtime.session.status == (stop ? .idle : .paused))
            await runtime.close(fixture)
        }
    }

    @Test("An obsolete filter failure does not terminate its replacement")
    @MainActor
    func supersededUpdateFailure() async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = try CaptureSessionFixture(fixture)
            let old = ControlledCaptureStream(), successor = ControlledCaptureStream()
            await fixture.track(runtime.provider.selectStream { old }).value
            let updating = fixture.gate(), release = fixture.gate()
            let update = fixture.track(runtime.provider.updateStream(old) {
                updating.open(); try await release.wait(); throw CaptureFixtureError.startFailed
            })
            try await updating.wait()
            let replacement = fixture.track(runtime.provider.selectStream { successor })
            runtime.provider.streamDidStop(old, error: CaptureFixtureError.startFailed)
            old.terminated = true; old.capturing = false
            release.open()
            await update.value; await replacement.value
            #expect(successor.capturing && runtime.session.status == .transcribing)
            await runtime.close(fixture)
        }
    }

    @Test("Terminal delegate errors survive a failed pause", arguments: [false, true])
    @MainActor
    func failedPauseWithTerminalEvent(duringStop: Bool) async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = try CaptureSessionFixture(fixture)
            let stream = ControlledCaptureStream()
            let (results, continuation) = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()
            runtime.session.continuation = .speech(continuation)
            await fixture.track(runtime.provider.selectStream { stream }).value
            stream.stopError = CaptureFixtureError.startFailed
            let terminate: @MainActor @Sendable () -> Void = {
                stream.terminated = true; stream.capturing = false
                runtime.provider.streamDidStop(stream, error: CaptureFixtureError.startFailed)
            }
            if duringStop { stream.onStop = terminate }
            await runtime.session.pauseTranscribing()
            if !duringStop {
                #expect(runtime.session.status == .transcribing && stream.capturing)
                terminate()
            }
            await #expect(throws: SpeechSessionError.self) {
                try await awaitResult(timeout: 3) { for try await _ in results {} }
            }
            #expect(runtime.session.status == .idle && !runtime.owner.isRunning)
            #expect(stream.stops == 1)
        }
    }

    @Test("A terminal event during start cannot resurrect capture", arguments: [false, true])
    @MainActor
    func terminalEventDuringStart(userStopped: Bool) async throws {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        try await withCaptureFixture { fixture in
            let runtime = try CaptureSessionFixture(fixture)
            let stream = ControlledCaptureStream()
            let started = fixture.gate(), release = fixture.gate()
            stream.startEntered = started; stream.startRelease = release
            let (results, continuation) = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()
            runtime.session.continuation = .speech(continuation)
            let selection = fixture.track(runtime.provider.selectStream { stream })
            try await started.wait()
            stream.terminated = true
            let error: Error = userStopped
                ? NSError(domain: SCStreamError.errorDomain, code: SCStreamError.Code.userStopped.rawValue)
                : CaptureFixtureError.startFailed
            runtime.provider.streamDidStop(stream, error: error)
            release.open()
            await selection.value
            do {
                try await awaitResult(timeout: 3) { for try await _ in results {} }
                #expect(userStopped)
            } catch is SpeechSessionError {
                #expect(!userStopped)
            }
            #expect(runtime.session.status == .idle && !runtime.owner.isRunning)
            #expect(!stream.capturing && stream.stops == 0)
        }
    }
}
#endif
