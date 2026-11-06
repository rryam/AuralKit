import Foundation
import Testing

@Suite("Timeout task ownership")
@MainActor
struct TestTimeoutHelpersTests {
    enum Exit: Sendable, CaseIterable { case timeout, cancelledBeforeWait, cancelledDuringWait }
    enum FixtureError: Error { case expected }

    @Test("Timeout and cancellation join stream consumers and producers", arguments: Exit.allCases)
    func streamTasksAreJoined(exit: Exit) async throws {
        let values = AsyncStream<Int>.makeStream()
        let producerGate = AsyncStream<Void>.makeStream()
        let ready = AsyncStream<Void>.makeStream()
        let state = CompletionState()
        let producer = Task<Int?, Never> { @MainActor in
            defer {
                state.producerFinished = true
                values.continuation.finish()
            }
            ready.continuation.yield(())
            var iterator = producerGate.stream.makeAsyncIterator()
            _ = await iterator.next()
            return nil
        }
        let consumer = Task { @MainActor in
            defer { state.consumerFinished = true }
            ready.continuation.yield(())
            var iterator = values.stream.makeAsyncIterator()
            return await iterator.next()
        }
        try await withOwnedTasks([producer, consumer]) {
            // Both tasks have entered their real stream waits before the race begins.
            let probe = AsyncStreamProbe(ready.stream)
            _ = try await awaitResult { await probe.next() }
            _ = try await awaitResult { await probe.next() }
            let entered = AsyncStream<Void>.makeStream()
            let waiter = Task { @MainActor in
                entered.continuation.yield(())
                return try await awaitResult(timeout: 0.02, task: consumer)
            }
            if exit == .cancelledBeforeWait {
                // No actor suspension since task creation: cancellation predates entry.
                waiter.cancel()
            } else if exit == .cancelledDuringWait {
                var iterator = entered.stream.makeAsyncIterator()
                _ = await iterator.next()
                waiter.cancel()
            }
            do {
                _ = try await waiter.value
                Issue.record("Expected timeout or cancellation")
            } catch is TestTimeoutError {
                #expect(exit == .timeout)
            } catch is CancellationError {
                #expect(exit != .timeout)
            }
            #expect(state.consumerFinished)
        }
        #expect(state.producerFinished)
        #expect(state.consumerFinished)
        producerGate.continuation.finish()
        ready.continuation.finish()
    }

    @Test("Values and operation errors propagate")
    func valuesAndErrors() async throws {
        let value = try await awaitResult { 42 }
        #expect(value == 42)
        let taskValue = try await awaitResult(task: Task { 43 })
        #expect(taskValue == 43)
        do {
            let _: Int = try await awaitResult { throw FixtureError.expected }
            Issue.record("Expected operation error")
        } catch FixtureError.expected { }
    }

    @Test("Throwing fixture scope cancels and joins its task")
    func throwingScopeJoins() async {
        let stream = AsyncStream<Int>.makeStream()
        let state = CompletionState()
        let task = Task { @MainActor in
            defer { state.consumerFinished = true }
            var iterator = stream.stream.makeAsyncIterator()
            return await iterator.next()
        }
        do {
            try await withOwnedTasks([task]) { throw FixtureError.expected }
        } catch { }
        #expect(state.consumerFinished)
        stream.continuation.finish()
    }
}

@MainActor
private final class CompletionState {
    var producerFinished = false
    var consumerFinished = false
}
