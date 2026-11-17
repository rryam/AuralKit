import AVFoundation
import Foundation
import Speech
import Testing
@testable import AuralKit

@Suite("File ingestion settlement")
@MainActor
struct FileIngestionSettlementTests {
    @Test("Independent ingestion cancellation settles the public stream", arguments: [false, true])
    func independentCancellation(throwsCancellation: Bool) async throws {
        try await withSession { runtime, fixture in
            runtime.session.startFileIngestion(generation: runtime.generation) { _ in
                if throwsCancellation { throw CancellationError() }
                withUnsafeCurrentTask { $0?.cancel() }
            }
            let input = fixture.track(try #require(runtime.session.fileIngestionTask))
            await #expect(throws: CancellationError.self) {
                try await awaitResult(timeout: 3) {
                    for try await _ in runtime.results { Issue.record("Unexpected result") }
                }
            }
            await input.value
            #expect(runtime.session.status == .idle)
            #expect(runtime.session.continuation == nil)
        }
    }

    @Test("Result EOF preserves a later input or finalization error", arguments: [false, true])
    func resultEOFDoesNotAdmitPrematureSuccess(finalization: Bool) async throws {
        try await withSession { runtime, fixture in
            let release = fixture.gate()
            let results = AsyncThrowingStream<Int, Error>.makeStream()
            let forwarded = AsyncThrowingStream<Int, Error>.makeStream()
            defer { forwarded.continuation.finish() }
            let reader = fixture.track(runtime.session.createRecognizerTask(
                label: "File result fixture", results: results.stream,
                streamContinuation: forwarded.continuation, generation: runtime.generation
            ))
            runtime.session.recognizerTask = reader
            if finalization {
                runtime.session.analyzer = SpeechAnalyzer(modules: [])
                runtime.session.analyzerInputTask = Task {
                    try await release.wait()
                    throw SpeechSessionError.invalidAudioDataType
                }
            }
            runtime.session.startFileIngestion(generation: runtime.generation) { session in
                if finalization {
                    try await session.finishFileInput(generation: runtime.generation)
                } else {
                    try await release.wait()
                    throw SpeechSessionError.audioFileReadFailed(nil)
                }
            }
            let input = fixture.track(try #require(runtime.session.fileIngestionTask))
            results.continuation.finish()
            await reader.value
            #expect(runtime.session.continuation != nil)
            release.open()
            await input.value
            do {
                try await awaitResult(timeout: 3) {
                    for try await _ in runtime.results { Issue.record("Unexpected result") }
                }
                Issue.record("Expected the producer failure")
            } catch SpeechSessionError.invalidAudioDataType {
                #expect(finalization)
            } catch SpeechSessionError.audioFileReadFailed {
                #expect(!finalization)
            }
            #expect(runtime.session.status == .idle)
        }
    }

    @Test("A result iterator that cancels itself before EOF fails the public stream")
    func selfCancelledResultEOF() async throws {
        try await withSession { runtime, fixture in
            let forwarded = AsyncThrowingStream<Int, Error>.makeStream()
            defer { forwarded.continuation.finish() }
            runtime.session.startFileIngestion(generation: runtime.generation) { _ in }
            let reader = fixture.track(runtime.session.createRecognizerTask(
                label: "Self-cancelled results", results: SelfCancelledResults(),
                streamContinuation: forwarded.continuation, generation: runtime.generation
            ))
            runtime.session.recognizerTask = reader
            await #expect(throws: CancellationError.self) {
                try await awaitResult(timeout: 3) {
                    for try await _ in runtime.results { Issue.record("Unexpected result") }
                }
            }
            await reader.value
            #expect(runtime.session.status == .idle)
        }
    }

    @Test("A physical short read fails before closing analyzer input")
    func physicalShortRead() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Aural-short-read-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true
        ))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
        buffer.frameLength = 160
        buffer.int16ChannelData?.pointee.initialize(repeating: 0, count: 160)
        try autoreleasepool {
            let writer = try AVAudioFile(
                forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true
            )
            try writer.write(from: buffer)
        }
        try await withSession { runtime, _ in
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
            let declaredFrames = file.length + 1
            let input = AsyncStream<AnalyzerInput>.makeStream()
            defer { input.continuation.finish() }
            runtime.session.inputBuilder = input.continuation
            runtime.session.analyzerFormat = format
            do {
                _ = try await runtime.session.feedAudioFile(
                    (file: file, totalFrames: declaredFrames), progressHandler: { _ in },
                    generation: runtime.generation
                )
                Issue.record("Expected audioFileReadFailed for premature physical EOF")
            } catch SpeechSessionError.audioFileReadFailed { }
            if case .terminated = input.continuation.yield(AnalyzerInput(buffer: buffer)) {
                Issue.record("Physical input closed before its read failure was admitted")
            }
        }
    }

    @MainActor
    private struct Runtime {
        let session: SpeechSession
        let results: AsyncThrowingStream<SpeechTranscriber.Result, Error>
        let generation: Int

        init() {
            let session = SpeechSession()
            let output = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()
            self.session = session
            results = output.stream
            generation = session.beginStreamGeneration()
            session.continuation = .speech(output.continuation)
            session.streamingMode = .filePlayback
            session.setStatus(.transcribing)
        }
    }

    private func withSession(_ body: (Runtime, CaptureFixture) async throws -> Void) async throws {
        try await withCaptureFixture { fixture in
            let runtime = Runtime()
            do {
                try await body(runtime, fixture)
            } catch {
                fixture.releaseAll()
                await runtime.session.cancelTranscribing()
                throw error
            }
            fixture.releaseAll()
            await runtime.session.cancelTranscribing()
        }
    }
}

private struct SelfCancelledResults: AsyncSequence, Sendable {
    typealias Element = Int
    struct AsyncIterator: AsyncIteratorProtocol {
        mutating func next() async -> Int? {
            withUnsafeCurrentTask { $0?.cancel() }
            return nil
        }
    }
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
}
