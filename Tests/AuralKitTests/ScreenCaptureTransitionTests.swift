import AVFoundation
import Speech
import Testing
@testable import AuralKit

/// Cancellation-independent latches: a cancelled operation still owns its OS call
/// until the fixture explicitly releases it. No readiness depends on scheduling delays.
@MainActor
private final class CaptureGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

@available(iOS 26.0, macOS 26.0, *)
@MainActor
private final class ControlledCaptureStream: ScreenCaptureStream {
    var starts = 0
    var stops = 0
    var capturing = false
    var startEntered: CaptureGate?
    var startRelease: CaptureGate?
    var stopEntered: CaptureGate?
    var stopRelease: CaptureGate?

    func startCapture() async throws {
        starts += 1
        startEntered?.open()
        await startRelease?.wait()
        capturing = true
    }

    func stopCapture() async throws {
        stops += 1
        stopEntered?.open()
        await stopRelease?.wait()
        capturing = false
    }
}

@Suite("Screen capture transitions")
struct ScreenCaptureTransitionTests {
    @Test("A picker replacement stopped across pause never starts the new stream")
    @MainActor
    func replacementHonorsAdmittedPause() async {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let owner = ScreenCaptureTransitions()
        let old = ControlledCaptureStream()
        let replacement = ControlledCaptureStream()
        let entered = CaptureGate()
        let release = CaptureGate()
        defer { release.open(); entered.open() }
        _ = try? await owner.replace { old }.value
        old.stopEntered = entered
        old.stopRelease = release
        let update = owner.replace { replacement }
        await entered.wait()
        let pause = owner.pause()
        #expect(owner.desiredState == .paused)
        release.open()
        _ = try? await update.value
        _ = try? await pause.value
        #expect(owner.stream === replacement)
        #expect(!owner.isRunning)
        #expect(!old.capturing)
        #expect(replacement.starts == 0)
        // A later explicit resume starts the selected stream, not the old one.
        _ = try? await owner.resume().value
        #expect(replacement.starts == 1)
        #expect(old.starts == 1)
        _ = try? await owner.stop().value
    }

    @Test("Overlapping picker replacements cannot install an obsolete stream after stop")
    @MainActor
    func replacementIdentityAcrossStop() async {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let owner = ScreenCaptureTransitions()
        let old = ControlledCaptureStream()
        let obsolete = ControlledCaptureStream()
        let current = ControlledCaptureStream()
        let entered = CaptureGate()
        let release = CaptureGate()
        defer { release.open(); entered.open() }
        _ = try? await owner.replace { old }.value
        old.stopEntered = entered
        old.stopRelease = release
        var obsoleteCreated = false
        let first = owner.replace { obsoleteCreated = true; return obsolete }
        await entered.wait()
        let second = owner.replace { current }
        release.open()
        _ = try? await first.value
        _ = try? await second.value
        #expect(!obsoleteCreated)
        #expect(obsolete.starts == 0)
        #expect(owner.stream === current)
        #expect(current.capturing)
        #expect(old.stops == 1)
        _ = try? await owner.stop().value
    }

    @Test("A superseded start compensates before its successor can start")
    @MainActor
    func replacementIdentityAcrossStart() async {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let owner = ScreenCaptureTransitions()
        let obsolete = ControlledCaptureStream()
        let current = ControlledCaptureStream()
        let startEntered = CaptureGate()
        let startRelease = CaptureGate()
        let stopEntered = CaptureGate()
        let stopRelease = CaptureGate()
        defer {
            startRelease.open(); stopRelease.open()
            startEntered.open(); stopEntered.open()
        }
        obsolete.startEntered = startEntered
        obsolete.startRelease = startRelease
        obsolete.stopEntered = stopEntered
        obsolete.stopRelease = stopRelease
        let first = owner.replace { obsolete }
        await startEntered.wait()
        let second = owner.replace { current }
        startRelease.open()
        await stopEntered.wait()
        #expect(current.starts == 0)
        #expect(owner.stream === obsolete)
        stopRelease.open()
        _ = try? await first.value
        _ = try? await second.value
        #expect(!obsolete.capturing)
        #expect(obsolete.stops == 1)
        #expect(owner.stream === current)
        #expect(current.starts == 1)
        #expect(owner.isRunning)
        _ = try? await owner.stop().value
    }
}

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit

extension ScreenCaptureTransitionTests {
    @Test("Detached provider shutdown joins late resume and compensating stop")
    @MainActor
    func shutdownJoinsLateProviderResume() async {
        guard #available(iOS 27.0, macOS 26.0, *) else { return }
        let owner = ScreenCaptureTransitions()
        let stream = ControlledCaptureStream()
        _ = try? await owner.replace { stream }.value
        _ = try? await owner.pause().value
        let startEntered = CaptureGate()
        let startRelease = CaptureGate()
        let stopEntered = CaptureGate()
        let stopRelease = CaptureGate()
        let dismissed = CaptureGate()
        defer {
            startRelease.open(); stopRelease.open()
            startEntered.open(); stopEntered.open(); dismissed.open()
        }
        stream.startEntered = startEntered
        stream.startRelease = startRelease
        stream.stopEntered = stopEntered
        stream.stopRelease = stopRelease
        let (_, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        defer { continuation.finish() }
        // Actual provider and actual detached cleanup interface. Only OS capture calls
        // and picker dismissal vary; no analyzer setup or public session state setters.
        let provider = ScreenCaptureAudioInputProvider(
            options: .init(),
            targetFormat: AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!,
            inputContinuation: continuation,
            onFailure: { _ in Issue.record("Unexpected provider failure") },
            transitions: owner,
            dismissPicker: { _ in dismissed.open() }
        )
        let session = SpeechSession()
        session.screenCaptureInputProvider = provider
        let resume = Task { @MainActor in try? await provider.resume() }
        await startEntered.wait()
        var terminalReturned = false
        let stop = Task { @MainActor in
            await session.stopScreenCaptureStreamingIfNeeded()
            terminalReturned = true
        }
        await dismissed.wait()
        #expect(owner.desiredState == .stopped)
        #expect(session.screenCaptureInputProvider == nil)
        #expect(!terminalReturned)
        startRelease.open()
        await stopEntered.wait()
        #expect(!terminalReturned)
        #expect(stream.capturing)
        stopRelease.open()
        await stop.value
        _ = await resume.value
        #expect(terminalReturned)
        #expect(!stream.capturing)
        #expect(stream.starts == 2)
        #expect(stream.stops == 2)
        #expect(owner.stream == nil)
        // Public stopTranscribing -> cleanup -> stopScreenCaptureStreamingIfNeeded
        // awaits this boundary before finalizeDetachedTranscriberState/releaseLocales.
        // Public resumeTranscribing is deliberately outside the joined operation chain:
        // its error path can await cleanup itself. Full public setup needs native analysis.
    }
}
#endif
