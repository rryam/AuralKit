import Foundation
import Dispatch
import AVFoundation
import Testing
@testable import AuralKit

@Suite("Live setup admission")
@MainActor
struct LiveSetupAdmissionTests {
    @Test("Cancelled format selection cannot repopulate stopped state", arguments: [false, true])
    func stoppedSelection(returnsNil: Bool) async throws {
        try await withSelection(returnsNil: returnsNil) { session, gate, task in
            try await gate.waitUntilEntered()
            task.cancel()
            await session.stopTranscribing()
            gate.release()
            let error = await task.value
            #expect(error is CancellationError)
            #expect(session.analyzerFormat == nil)
            #expect(session.inputSequence == nil)
            #expect(session.inputBuilder == nil)
        }
    }

    @Test("Replaced format selection and its catch cannot publish into a successor",
          arguments: [false, true])
    func replacedSelection(returnsNil: Bool) async throws {
        try await withSelection(returnsNil: returnsNil) { session, gate, task in
            let oldGeneration = session.sessionGeneration
            try await gate.waitUntilEntered()
            await session.stopTranscribing()
            // This is the same generation admission used by public starts. Leave the old
            // task uncancelled to exercise generation rejection independently of cancellation.
            _ = session.beginStreamGeneration()
            gate.release()
            let error = await task.value
            #expect(error is CancellationError)
            #expect(session.analyzerFormat == nil)
            #expect(session.inputSequence == nil)
            #expect(session.inputBuilder == nil)

            // Public start installs the actual successor setup handle. Cancel synchronously
            // before it can enter permissions/models; no native setup is faked or invoked.
            let staleError = try #require(error)
            let stream = session.startTranscribing()
            // No throwing assertion may leave this task unjoined.
            let successor = session.pipelineTask
            successor?.cancel()
            await session.finishFailedPipelineSetup(staleError, generation: oldGeneration)
            #expect(session.pipelineTask != nil)
            #expect(session.continuation != nil)
            await session.finishFailedPipelineSetup(
                SpeechSessionError.invalidAudioDataType, generation: oldGeneration
            )
            #expect(session.pipelineTask != nil)
            #expect(session.continuation != nil)
            await session.stopTranscribing()
            await successor?.value
            withExtendedLifetime(stream) {}
        }
    }

    @Test("Current selection reaches the owning format and stream writes",
          arguments: [false, true])
    func currentSelection(returnsNil: Bool) async throws {
        try await withSelection(returnsNil: returnsNil) { session, gate, task in
            try await gate.waitUntilEntered()
            gate.release()
            let error = await task.value
            // No analyzer/model is installed in this helper-level fixture. A valid format
            // reaches the real writes, then fails the existing missing-analyzer guard.
            #expect(error is SpeechSessionError)
            #expect((session.analyzerFormat == nil) == returnsNil)
            #expect((session.inputSequence == nil) == returnsNil)
            #expect((session.inputBuilder == nil) == returnsNil)
        }
    }

    private func withSelection(
        returnsNil: Bool,
        body: (SpeechSession, FormatGate, Task<Error?, Never>) async throws -> Void
    ) async throws {
        let session = SpeechSession()
        let gate = FormatGate()
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let generation = session.beginStreamGeneration()
        let task = Task<Error?, Never> { @MainActor in
            do {
                try await session.startAnalyzer(modules: [], generation: generation) { _ in
                    await gate.select(returnsNil ? nil : format)
                }
                return nil
            } catch {
                return error
            }
        }
        do {
            try await body(session, gate, task)
        } catch {
            gate.release()
            task.cancel()
            _ = await task.value
            await session.stopTranscribing()
            throw error
        }
        gate.release()
        task.cancel()
        _ = await task.value
        await session.stopTranscribing()
    }
}

/// A deliberately cancellation-ignoring native format lookup. Entry is event-driven;
/// release is persistent, including when fixture cleanup precedes selection entry.
@MainActor
private final class FormatGate {
    private let entered: AsyncStream<Void>
    private let entry: AsyncStream<Void>.Continuation
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var released = false

    init() {
        (entered, entry) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func select(_ format: AVAudioFormat?) async -> AVAudioFormat? {
        entry.yield(())
        entry.finish()
        if !released {
            await withCheckedContinuation { releaseContinuation = $0 }
        }
        return format
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
        entry.finish()
    }

    func waitUntilEntered() async throws {
        let events = entered
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var iterator = events.makeAsyncIterator()
                guard await iterator.next() != nil else { throw CancellationError() }
                try Task.checkCancellation()
            }
            group.addTask {
                // Deadline only; entry events, never elapsed time, sequence the test.
                let (ticks, tick) = AsyncStream<Void>.makeStream()
                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now() + 2)
                timer.setEventHandler {
                    tick.yield(())
                    tick.finish()
                }
                timer.resume()
                defer { timer.cancel() }
                var iterator = ticks.makeAsyncIterator()
                _ = await iterator.next()
                try Task.checkCancellation()
                throw TestTimeoutError.timedOut(seconds: 2)
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }
}
