import Foundation
import Testing
@testable import AuralKit

@Suite("Speech detector monitor identity")
struct SpeechDetectorLifecycleTests {
    @Test("public disable and reconfigure rejects a late predecessor result")
    @MainActor
    func staleResultAfterReconfiguration() async throws {
        try await withFixture { fixture in
            let source = HeldDetectorSource()
            fixture.sources.append(source)
            fixture.session.configureVoiceActivation(reportResults: true)
            let old = try fixture.monitor(HeldDetectorResults(source: source))
            try await fixture.waitUntil { await source.isWaiting }
            fixture.session.disableVoiceActivation()
            fixture.session.configureVoiceActivation(reportResults: true)
            let (results, continuation) = fixture.results()
            _ = try fixture.monitor(results)
            let currentID = try #require(fixture.session.speechDetectorMonitorID)
            continuation.yield(true)
            try await fixture.waitUntil { fixture.values == [true] }
            await source.send(false)
            await source.finish()
            #expect(old.isCancelled)
            await old.value
            #expect(fixture.values == [true])
            #expect(fixture.session.isSpeechDetected)
            #expect(fixture.session.speechDetectorMonitorID == currentID)
            #expect(fixture.session.speechDetectorResultsTask != nil)
            #expect(fixture.session.speechDetectorResultsStream != nil)
        }
    }

    @Test("predecessor completion cannot finish a reconfigured monitor", arguments: [false, true])
    @MainActor
    func staleCompletionAfterReconfiguration(failed: Bool) async throws {
        try await withFixture { fixture in
            fixture.session.configureVoiceActivation(reportResults: true)
            let source = HeldDetectorSource()
            fixture.sources.append(source)
            let old = try fixture.monitor(HeldDetectorResults(source: source))
            try await fixture.waitUntil { await source.isWaiting }
            fixture.session.disableVoiceActivation()
            fixture.session.configureVoiceActivation(reportResults: true)
            let (results, input) = fixture.results()
            _ = try fixture.monitor(results)
            let currentID = try #require(fixture.session.speechDetectorMonitorID)
            input.yield(false)
            try await fixture.waitUntil { fixture.values == [false] }
            if failed { await source.fail() } else { await source.finish() }
            #expect(old.isCancelled)
            await old.value
            #expect(!fixture.session.isSpeechDetected)
            #expect(fixture.session.speechDetectorMonitorID == currentID)
            #expect(fixture.session.speechDetectorResultsTask != nil)
            #expect(fixture.session.speechDetectorResultsContinuation != nil)
            #expect(fixture.session.speechDetectorResultsStream != nil)
        }
    }

    @Test("cooperative cancellation of a replaced reader cannot clear its successor")
    @MainActor
    func cancelledPredecessorCompletion() async throws {
        try await withFixture { fixture in
            fixture.session.configureVoiceActivation(reportResults: true)
            let (oldResults, oldInput) = fixture.results()
            let old = try fixture.monitor(oldResults)
            oldInput.yield(true)
            try await fixture.waitUntil { fixture.values == [true] }
            let (results, input) = fixture.results()
            _ = try fixture.monitor(results)
            let currentID = try #require(fixture.session.speechDetectorMonitorID)
            await old.value
            #expect(old.isCancelled)
            #expect(fixture.session.speechDetectorMonitorID == currentID)
            #expect(fixture.session.speechDetectorResultsTask != nil)
            #expect(fixture.session.speechDetectorResultsStream != nil)
            input.yield(false)
            try await fixture.waitUntil { fixture.values == [true, false] }
            #expect(!fixture.session.isSpeechDetected)
        }
    }

    @Test("disable revokes a reader even without a replacement")
    @MainActor
    func staleResultAfterDisable() async throws {
        try await withFixture { fixture in
            let source = HeldDetectorSource()
            fixture.sources.append(source)
            fixture.session.configureVoiceActivation(reportResults: true)
            let old = try fixture.monitor(HeldDetectorResults(source: source))
            try await fixture.waitUntil { await source.isWaiting }
            fixture.session.disableVoiceActivation()
            await source.send(false)
            await source.finish()
            await old.value
            #expect(old.isCancelled)
            #expect(fixture.values.isEmpty)
            #expect(fixture.session.isSpeechDetected)
            #expect(fixture.session.speechDetectorMonitorID == nil)
            #expect(fixture.session.speechDetectorResultsTask == nil)
            #expect(fixture.session.speechDetectorResultsStream == nil)
        }
    }

    @Test("current results and normal or failed completion retain their behavior", arguments: [false, true])
    @MainActor
    func currentMonitorCompletion(failed: Bool) async throws {
        try await withFixture { fixture in
            fixture.session.configureVoiceActivation(reportResults: true)
            let (results, input) = fixture.results()
            let task = try fixture.monitor(results)
            input.yield(false)
            try await fixture.waitUntil { fixture.values == [false] }
            #expect(!fixture.session.isSpeechDetected)
            if failed { input.finish(throwing: DetectorTestError.failed) } else { input.finish() }
            await task.value
            #expect(fixture.session.isSpeechDetected)
            #expect(fixture.session.speechDetectorMonitorID == nil)
            #expect(fixture.session.speechDetectorResultsTask == nil)
            #expect(fixture.session.speechDetectorResultsContinuation == nil)
            #expect(fixture.session.speechDetectorResultsStream == nil)
        }
    }

    @MainActor
    private func withFixture(_ operation: @MainActor (DetectorFixture) async throws -> Void) async throws {
        let fixture = DetectorFixture()
        do { try await operation(fixture) } catch { await fixture.cleanup(); throw error }
        await fixture.cleanup()
    }
}

private enum DetectorTestError: Error {
    case failed
}

/// Holds a suspended next() across cancellation to exercise a late value or
/// completion. This models the AsyncSequence contract, not Apple implementation timing.
private actor HeldDetectorSource {
    private var continuation: CheckedContinuation<Bool?, Error>?
    private var finished = false
    private(set) var isWaiting = false

    func next() async throws -> Bool? {
        guard !finished else { return nil }
        isWaiting = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func send(_ value: Bool) {
        isWaiting = false
        continuation?.resume(returning: value)
        continuation = nil
    }

    func fail() {
        finished = true
        isWaiting = false
        continuation?.resume(throwing: DetectorTestError.failed)
        continuation = nil
    }

    func finish() {
        finished = true
        isWaiting = false
        continuation?.resume(returning: nil)
        continuation = nil
    }
}

private struct HeldDetectorResults: AsyncSequence, Sendable {
    typealias Element = Bool
    let source: HeldDetectorSource

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(source: source)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        let source: HeldDetectorSource

        mutating func next() async throws -> Bool? {
            try await source.next()
        }
    }
}

@MainActor
private final class DetectorFixture {
    let session = SpeechSession()
    var values: [Bool] = []
    var sources: [HeldDetectorSource] = []
    private var tasks: [Task<Void, Never>] = []
    private var inputs: [AsyncThrowingStream<Bool, Error>.Continuation] = []

    func results() -> (
        AsyncThrowingStream<Bool, Error>,
        AsyncThrowingStream<Bool, Error>.Continuation
    ) {
        let (results, input) = AsyncThrowingStream<Bool, Error>.makeStream()
        inputs.append(input)
        return (results, input)
    }

    func monitor<Sequence: AsyncSequence>(_ results: Sequence) throws -> Task<Void, Never>
    where Sequence: Sendable, Sequence.Element == Bool {
        session.monitorSpeechDetectorResults(
            results,
            speechDetected: { $0 },
            onResult: { [unowned self] detected in
                values.append(detected)
            }
        )
        let task = try #require(session.speechDetectorResultsTask)
        tasks.append(task)
        return task
    }

    func waitUntil(_ predicate: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else { throw TestTimeoutError.timedOut(seconds: 2) }
            await Task.yield()
        }
    }

    func cleanup() async {
        session.disableVoiceActivation()
        for source in sources { await source.finish() }
        inputs.forEach { $0.finish() }
        tasks.forEach { $0.cancel() }
        for task in tasks { await task.value }
    }
}
