import Foundation
import Testing
@testable import AuralKit

/// Harness waits cooperate; simulated native operations explicitly opt out.
@MainActor
private final class FileJoinGate {
    private var opened = false
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    var pendingControlWaits: Int { waiters.count }

    func wait() async throws {
        try Task.checkCancellation()
        if opened { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiters[id] = continuation
            }
        } onCancel: {
            Task { @MainActor in
                self.waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
            }
        }
    }

    func waitIgnoringCancellation() async {
        if opened { return }
        await withCheckedContinuation { operationWaiters.append($0) }
    }

    func open() {
        opened = true
        let pending = Array(waiters.values)
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
        let operations = operationWaiters
        operationWaiters.removeAll()
        for waiter in operations { waiter.resume() }
    }
}

@Suite("Joined file retirement")
@MainActor
struct FileTranscriptionJoinTests {
    /// The watchdog is independent of the body and its readiness waits. Cleanup
    /// releases even cancellation-insensitive simulated native operations first.
    @discardableResult
    private func withRun(
        failFinalization: Bool = false,
        timeout: Duration = .seconds(5),
        expectTimeout: Bool = false,
        _ body: @escaping @MainActor (FileTranscriptionRun, [FileJoinGate], AsyncThrowingStream<Int, Error>,
                 AsyncThrowingStream<Int, Error>.Continuation, FileJoinRecord) async throws -> Void
    ) async -> FileJoinRecord {
        let gates = (0..<6).map { _ in FileJoinGate() }
        let finished = FileJoinGate()
        let record = FileJoinRecord()
        let (stream, continuation) = AsyncThrowingStream<Int, Error>.makeStream()
        let run = FileTranscriptionRun(finalize: { alreadyFinalized in
            record.events.append("detach")
            gates[3].open()
            if !alreadyFinalized {
                record.events.append("finalize")
                await gates[4].waitIgnoringCancellation()
                if failFinalization { throw CocoaError(.fileReadUnknown) }
                continuation.yield(42)
                continuation.finish()
            }
        }, complete: { error in
            record.error = error
            record.events.append("complete")
        })
        let work = Task {
            do { try await body(run, gates, stream, continuation, record) }
            catch is CancellationError { }
            catch { Issue.record("Unexpected harness error: \(error)") }
            finished.open()
        }
        let watchdog = Task {
            do { try await Task.sleep(for: timeout) } catch { return }
            record.timedOut = true
            finished.open()
        }
        try? await finished.wait()
        watchdog.cancel()
        work.cancel()
        for gate in gates { gate.open() }
        continuation.finish()
        await run.requestRetirement().value
        await work.value
        await watchdog.value
        #expect(record.timedOut == expectTimeout)
        #expect(gates.allSatisfy { $0.pendingControlWaits == 0 })
        #expect(record.events.contains("complete"))
        return record
    }

    @Test("Stop joins suspended setup and a late-installed reader")
    func stopDuringSetup() async {
        await withRun { run, gates, stream, _, record in
            run.startSetup {
                gates[0].open()
                await gates[1].waitIgnoringCancellation()
                run.startResults(stream) { record.values.append($0) }
                run.startIngestion { record.events.append("unexpected input"); return true }
                record.events.append("setup exited")
            }
            try await gates[0].wait()
            let terminal = run.requestRetirement()
            gates[1].open()
            try await gates[3].wait()
            #expect(record.events == ["setup exited", "detach", "finalize"])
            gates[4].open()
            await terminal.value
            #expect(record.values == [42])
            #expect(record.events.last == "complete")
        }
    }

    @Test("Stop joins input before finalization and concurrent callers share completion")
    func stopDuringInput() async {
        await withRun { run, gates, stream, _, record in
            run.startSetup {
                run.startResults(stream) { record.values.append($0) }
                run.startIngestion {
                    gates[0].open()
                    await gates[1].waitIgnoringCancellation()
                    record.events.append("input exited")
                    return true
                }
            }
            try await gates[0].wait()
            let first = Task { await run.requestRetirement().value; record.events.append("stop one") }
            let second = Task { await run.requestRetirement().value; record.events.append("stop two") }
            // Latch before releasing the input; the two Tasks join that same owner.
            let terminal = run.requestRetirement()
            gates[1].open()
            try await gates[3].wait()
            #expect(record.events == ["input exited", "detach", "finalize"])
            gates[4].open()
            await terminal.value
            await first.value
            await second.value
            #expect(record.events.filter { $0 == "finalize" }.count == 1)
            #expect(Array(record.events.prefix(4)) == ["input exited", "detach", "finalize", "complete"])
            #expect(Set(record.events.suffix(2)) == Set(["stop one", "stop two"]))
            #expect(record.error == nil)
        }
    }

    @Test("Finalizer-generated results drain before completion")
    func finalResultDrain() async {
        await withRun { run, gates, stream, _, record in
            run.startSetup {
                run.startResults(stream) { record.values.append($0); record.events.append("result") }
                run.startIngestion { gates[0].open(); return true }
            }
            try await gates[0].wait()
            let terminal = run.requestRetirement()
            try await gates[3].wait()
            #expect(record.values.isEmpty)
            #expect(!record.events.contains("complete"))
            gates[4].open()
            await terminal.value
            #expect(record.values == [42])
            #expect(record.events.suffix(2) == ["result", "complete"])
        }
    }

    @Test("Natural reader completion joins ingestion without cancelling it")
    func naturalCompletion() async {
        await withRun { run, gates, stream, continuation, record in
            run.startSetup {
                run.startResults(stream) { record.values.append($0) }
                run.startIngestion {
                    gates[0].open()
                    await gates[1].waitIgnoringCancellation()
                    #expect(!Task.isCancelled)
                    record.events.append("input exited")
                    return true
                }
            }
            try await gates[0].wait()
            continuation.finish()
            gates[1].open()
            try await gates[3].wait()
            gates[4].open()
            await run.terminalTask?.value
            #expect(record.events == ["input exited", "detach", "finalize", "complete"])
            #expect(record.error == nil)
        }
    }

    @Test("Finalizer failure cancels and joins a waiting reader")
    func finalizationFailure() async {
        await withRun(failFinalization: true) { run, gates, stream, continuation, record in
            continuation.onTermination = { termination in
                let cancelled: Bool
                if case .cancelled = termination { cancelled = true } else { cancelled = false }
                Task { @MainActor in
                    record.readerWasCancelled = cancelled
                    gates[2].open()
                }
            }
            run.startSetup {
                run.startResults(stream) { record.values.append($0) }
                gates[0].open()
            }
            try await gates[0].wait()
            let terminal = run.requestRetirement()
            try await gates[3].wait()
            gates[4].open()
            await terminal.value
            try await gates[2].wait()
            #expect(record.readerWasCancelled)
            #expect(record.error is CocoaError)
            #expect(record.events.last == "complete")
        }
    }

    @Test("Independent result cancellation settles the stream")
    func readerCancellation() async {
        await withRun { run, gates, stream, continuation, record in
            run.startSetup {
                run.startResults(stream) { record.values.append($0) }
                gates[0].open()
            }
            try await gates[0].wait()
            continuation.finish(throwing: CancellationError())
            try await gates[3].wait()
            gates[4].open()
            // Finalization was reached by the reader's request, without public stop.
            await run.terminalTask?.value
            #expect(record.error is CancellationError)
        }
    }

    @Test("Stop preserves a later genuine producer failure", arguments: ["reader", "input", "setup"])
    func realErrorAfterStop(producer: String) async {
        await withRun { run, gates, stream, continuation, record in
            run.startSetup {
                run.startResults(stream) { record.values.append($0) }
                if producer == "setup" {
                    gates[0].open()
                    await gates[1].waitIgnoringCancellation()
                    throw FileJoinFailure.first
                }
                run.startIngestion {
                    gates[0].open()
                    await gates[1].waitIgnoringCancellation()
                    if producer == "input" { throw FileJoinFailure.first }
                    return true
                }
            }
            try await gates[0].wait()
            let terminal = run.requestRetirement()
            if producer == "reader" { continuation.finish(throwing: FileJoinFailure.first) }
            gates[1].open()
            try await gates[3].wait()
            gates[4].open()
            await terminal.value
            #expect(record.error as? FileJoinFailure == .first)
        }
    }

    @Test("Meaningful error priority survives later cleanup cancellation", arguments: [false, true])
    func errorPriority(initialCancellation: Bool) async {
        await withRun { run, gates, stream, continuation, record in
            run.startSetup {
                run.startResults(stream) { record.values.append($0) }
                run.startIngestion {
                    gates[0].open()
                    await gates[1].waitIgnoringCancellation()
                    throw CancellationError()
                }
            }
            try await gates[0].wait()
            let initial: Error = initialCancellation ? CancellationError() : FileJoinFailure.first
            let terminal = run.requestRetirement(error: initial)
            continuation.finish(throwing: FileJoinFailure.second)
            gates[1].open()
            try await gates[3].wait()
            gates[4].open()
            await terminal.value
            #expect(record.error as? FileJoinFailure == (initialCancellation ? .second : .first))
        }
    }

    @Test("Normal input finalization is attempted once and its results drain",
          arguments: [false, true], [false, true])
    func normalFinalization(fails: Bool, stopDuringFinalization: Bool) async {
        await withRun { run, gates, stream, continuation, record in
            run.startSetup {
                run.startResults(stream) { record.values.append($0); record.events.append("result") }
                run.startIngestion {
                    try await run.finishInput {
                        record.events.append("normal finalize")
                        gates[0].open()
                        await gates[1].waitIgnoringCancellation()
                        if fails { throw FileJoinFailure.first }
                        continuation.yield(7)
                        continuation.finish()
                    }
                    return true
                }
            }
            try await gates[0].wait()
            if stopDuringFinalization { run.requestRetirement() }
            // A successful reader EOF requests retirement; a failed finalization
            // requests it from ingestion. Neither route may retry the operation.
            gates[1].open()
            try await gates[3].wait()
            await run.terminalTask?.value
            #expect(record.events.filter { $0 == "normal finalize" }.count == 1)
            #expect(!record.events.contains("finalize"))
            #expect(record.events.last == "complete")
            if fails {
                #expect(record.error as? FileJoinFailure == .first)
            } else {
                #expect(record.error == nil)
                #expect(record.values == [7])
                if let result = record.events.firstIndex(of: "result"),
                   let complete = record.events.firstIndex(of: "complete") {
                    #expect(result < complete)
                } else { Issue.record("Missing result or completion") }
            }
        }
    }

    @Test("Watchdog releases stalled body/readiness and joins native operations", arguments: [false, true])
    func watchdogCleanup(stallOnTerminal: Bool) async {
        let record = await withRun(timeout: .seconds(1), expectTimeout: true) { run, gates, stream, _, record in
            run.startSetup {
                run.startResults(stream) { record.values.append($0) }
                run.startIngestion {
                    gates[0].open()
                    await gates[1].waitIgnoringCancellation()
                    record.events.append("released input")
                    return true
                }
            }
            try await gates[0].wait()
            // Intentionally never signalled by a producer. The watchdog must
            // cancel this wait, release input/finalization, close and join.
            if stallOnTerminal {
                await run.requestRetirement().value
            } else {
                try await gates[5].wait()
            }
        }
        #expect(record.events.contains("released input"))
        #expect(record.events.last == "complete")
        #expect(record.error == nil)
    }

    @Test("Cancelling a harness wait removes its continuation")
    func cancelledControlWait() async {
        await withRun { _, gates, _, _, _ in
            let waiter = Task {
                gates[0].open()
                try await gates[1].wait()
            }
            try await gates[0].wait()
            #expect(gates[1].pendingControlWaits == 1)
            waiter.cancel()
            do {
                try await waiter.value
                Issue.record("Cancelled control wait returned successfully")
            } catch {
                #expect(error is CancellationError)
            }
            #expect(gates[1].pendingControlWaits == 0)
        }
    }

    @Test("Incomplete input and independent input cancellation are failures", arguments: [false, true])
    func incompleteInput(cancelled: Bool) async {
        await withRun { run, gates, stream, _, record in
            run.startSetup {
                run.startResults(stream) { record.values.append($0) }
                run.startIngestion {
                    if cancelled { throw CancellationError() }
                    return false
                }
            }
            try await gates[3].wait()
            gates[4].open()
            await run.terminalTask?.value
            if cancelled {
                #expect(record.error is CancellationError)
            } else {
                #expect(record.error is SpeechSessionError)
            }
        }
    }
}

@MainActor
private final class FileJoinRecord {
    var events: [String] = []
    var values: [Int] = []
    var error: Error?
    var timedOut = false
    var readerWasCancelled = false
}

private enum FileJoinFailure: Error {
    case first
    case second
}
