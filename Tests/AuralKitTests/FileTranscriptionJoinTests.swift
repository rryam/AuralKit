import Foundation
import Testing
@testable import AuralKit

/// Deliberately ignores cancellation so a join must await the actual operation.
@MainActor
private final class FileJoinGate {
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

@Suite("Joined file retirement")
@MainActor
struct FileTranscriptionJoinTests {
    /// Every test body is nonthrowing. Always release gates, close the sequence,
    /// and join the owner, even when an expectation records a failure.
    private func withRun(
        failFinalization: Bool = false,
        _ body: (FileTranscriptionRun, [FileJoinGate], AsyncThrowingStream<Int, Error>,
                 AsyncThrowingStream<Int, Error>.Continuation, FileJoinRecord) async -> Void
    ) async {
        let gates = (0..<6).map { _ in FileJoinGate() }
        let record = FileJoinRecord()
        let (stream, continuation) = AsyncThrowingStream<Int, Error>.makeStream()
        let run = FileTranscriptionRun(finalize: {
            record.events.append("finalize")
            gates[3].open()
            await gates[4].wait()
            if failFinalization { throw CocoaError(.fileReadUnknown) }
            continuation.yield(42)
            continuation.finish()
        }, complete: { error in
            record.error = error
            record.events.append("complete")
        })
        await body(run, gates, stream, continuation, record)
        for gate in gates { gate.open() }
        continuation.finish()
        await run.requestRetirement().value
    }

    @Test("Stop joins suspended setup and a late-installed reader")
    func stopDuringSetup() async {
        await withRun { run, gates, stream, _, record in
            run.startSetup {
                gates[0].open()
                await gates[1].wait()
                run.startResults(stream) { record.values.append($0) }
                run.startIngestion { record.events.append("unexpected input"); return true }
                record.events.append("setup exited")
            }
            await gates[0].wait()
            let terminal = run.requestRetirement()
            gates[1].open()
            await gates[3].wait()
            #expect(record.events == ["setup exited", "finalize"])
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
                    await gates[1].wait()
                    record.events.append("input exited")
                    return true
                }
            }
            await gates[0].wait()
            let first = Task { await run.requestRetirement().value; record.events.append("stop one") }
            let second = Task { await run.requestRetirement().value; record.events.append("stop two") }
            // Latch before releasing the input; the two Tasks join that same owner.
            let terminal = run.requestRetirement()
            gates[1].open()
            await gates[3].wait()
            #expect(record.events == ["input exited", "finalize"])
            gates[4].open()
            await terminal.value
            await first.value
            await second.value
            #expect(record.events.filter { $0 == "finalize" }.count == 1)
            #expect(Array(record.events.prefix(3)) == ["input exited", "finalize", "complete"])
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
            await gates[0].wait()
            let terminal = run.requestRetirement()
            await gates[3].wait()
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
                    await gates[1].wait()
                    #expect(!Task.isCancelled)
                    record.events.append("input exited")
                    return true
                }
            }
            await gates[0].wait()
            continuation.finish()
            gates[1].open()
            await gates[3].wait()
            gates[4].open()
            await run.terminalTask?.value
            #expect(record.events == ["input exited", "finalize", "complete"])
            #expect(record.error == nil)
        }
    }

    @Test("Finalizer failure cancels and joins a waiting reader")
    func finalizationFailure() async {
        await withRun(failFinalization: true) { run, gates, stream, _, record in
            run.startSetup {
                run.startResults(stream) { record.values.append($0) }
                gates[0].open()
            }
            await gates[0].wait()
            let terminal = run.requestRetirement()
            await gates[3].wait()
            gates[4].open()
            await terminal.value
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
            await gates[0].wait()
            continuation.finish(throwing: CancellationError())
            await gates[3].wait()
            gates[4].open()
            // Finalization was reached by the reader's request, without public stop.
            await run.terminalTask?.value
            #expect(record.error is CancellationError)
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
            await gates[3].wait()
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
}
