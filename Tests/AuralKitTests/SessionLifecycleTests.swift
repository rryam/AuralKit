import Testing
import AVFoundation
import Speech
@testable import AuralKit

@Suite("SpeechSession Lifecycle")
struct SpeechSessionLifecycleTests {

    /// A second `startTranscribing()` while a session is active must fail without tearing
    /// down the active session's state.
    @Test("Rejected concurrent start leaves the active session untouched")
    @MainActor
    func rejectedConcurrentStartLeavesActiveSessionUntouched() async throws {
        let session = SpeechSession()

        // Simulate an active live session.
        session.streamingMode = .liveMicrophone
        session.setStatus(.transcribing)

        let stream = session.startTranscribing()

        await #expect(throws: SpeechSessionError.self) {
            for try await _ in stream {}
        }

        // Give any (incorrectly) scheduled termination cleanup a chance to run.
        try await Task.sleep(for: .milliseconds(100))

        #expect(session.streamingMode == .liveMicrophone)
        #expect(session.status == .transcribing)

        session.streamingMode = .inactive
        session.setStatus(.idle)
    }

    /// Cancelling the consumer's iteration task must release the stored continuation so the
    /// session can be started again later.
    @Test("Stream termination releases the stored continuation")
    @MainActor
    func streamTerminationReleasesContinuation() async throws {
        let session = SpeechSession()

        let (_, continuation) = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()
        session.continuation = .speech(continuation)

        await session.handleStreamTermination(generation: session.sessionGeneration)

        #expect(session.continuation == nil)
        #expect(session.status == .idle)
        #expect(session.streamingMode == .inactive)
    }

    /// A termination handler from an older stream generation must not touch the state of a
    /// newer session.
    @Test("Stale stream termination is ignored")
    @MainActor
    func staleStreamTerminationIsIgnored() async throws {
        let session = SpeechSession()

        let staleGeneration = session.beginStreamGeneration()
        _ = session.beginStreamGeneration()

        let (_, continuation) = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()
        session.continuation = .speech(continuation)
        session.streamingMode = .liveMicrophone
        session.setStatus(.transcribing)

        await session.handleStreamTermination(generation: staleGeneration)

        #expect(session.continuation != nil)
        #expect(session.streamingMode == .liveMicrophone)
        #expect(session.status == .transcribing)

        continuation.finish()
        session.continuation = nil
        session.streamingMode = .inactive
        session.setStatus(.idle)
    }

    /// Stale cleanup calls (e.g. from a cancelled pipeline of a previous stream) must not
    /// tear down a newer session's state.
    @Test("Stale cleanup is ignored")
    @MainActor
    func staleCleanupIsIgnored() async throws {
        let session = SpeechSession()

        let staleGeneration = session.beginStreamGeneration()
        _ = session.beginStreamGeneration()

        session.streamingMode = .filePlayback
        session.setStatus(.transcribing)

        await session.cleanup(cancelRecognizer: true, generation: staleGeneration)

        #expect(session.streamingMode == .filePlayback)
        #expect(session.status == .transcribing)

        session.streamingMode = .inactive
        session.setStatus(.idle)
    }

    /// Pausing is only meaningful for live capture; during file transcription it must be
    /// refused (previously, resuming a "paused" file session started the microphone).
    @Test("Pause is refused during file transcription")
    @MainActor
    func pauseIsRefusedDuringFileTranscription() async throws {
        let session = SpeechSession()

        session.streamingMode = .filePlayback
        session.setStatus(.transcribing)

        await session.pauseTranscribing()

        #expect(session.status == .transcribing)

        session.streamingMode = .inactive
        session.setStatus(.idle)
    }

    /// Resuming must never start the microphone for a non-live streaming mode.
    @Test("Resume is refused during file transcription")
    @MainActor
    func resumeIsRefusedDuringFileTranscription() async throws {
        let session = SpeechSession()

        session.streamingMode = .filePlayback
        session.setStatus(.paused)

        try await session.resumeTranscribing()

        #expect(session.status == .paused)
        #expect(session.isAudioStreaming == false)

        session.streamingMode = .inactive
        session.setStatus(.idle)
    }
}

@Suite("BufferConverter")
struct BufferConverterTests {

    private func makeBuffer(sampleRate: Double, channels: AVAudioChannelCount) throws -> AVAudioPCMBuffer {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        return buffer
    }

    /// The converter must adapt when the input format changes mid-session (e.g. after an
    /// audio route change swaps the capture device).
    @Test("Converter survives input format changes")
    func converterSurvivesInputFormatChanges() throws {
        let converter = BufferConverter()
        let targetFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))

        let first = try converter.convertBuffer(
            try makeBuffer(sampleRate: 44_100, channels: 1),
            to: targetFormat
        )
        #expect(first.format == targetFormat)
        #expect(first.frameLength > 0)

        // Same target, different source format — previously reused the stale converter.
        let second = try converter.convertBuffer(
            try makeBuffer(sampleRate: 48_000, channels: 2),
            to: targetFormat
        )
        #expect(second.format == targetFormat)
        #expect(second.frameLength > 0)
    }

    /// Matching formats pass the buffer through untouched.
    @Test("Converter passes through matching formats")
    func converterPassesThroughMatchingFormats() throws {
        let converter = BufferConverter()
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        buffer.frameLength = 512

        let result = try converter.convertBuffer(buffer, to: format)
        #expect(result === buffer)
    }
}
