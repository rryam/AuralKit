import Foundation
@testable import AuralKit

enum CaptureFixtureError: Error { case deadline, startFailed }

/// Each waiter owns its deadline and can be removed by cancellation. No timeout
/// task group can be stranded joining a checked continuation that ignores cancel.
@MainActor
final class CaptureGate {
    private var opened = false
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    var waiterCount: Int { waiters.count }

    func wait(timeoutNanoseconds: UInt64 = 3_000_000_000) async throws {
        try Task.checkCancellation()
        if opened { return }
        let id = UUID()
        let deadline = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: timeoutNanoseconds) } catch { return }
            self.remove(id, error: CaptureFixtureError.deadline)
        }
        defer { deadline.cancel() }
        try await withTaskCancellationHandler { () async throws -> Void in
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor in self.remove(id, error: CancellationError()) }
        }
    }

    private func remove(_ id: UUID, error: Error) {
        waiters.removeValue(forKey: id)?.resume(throwing: error)
    }

    func open() {
        opened = true
        let pending = waiters.values
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

/// Async cleanup opens all gates before joining every task admitted by the test,
/// including on a failed readiness wait. Errors remain visible to the test body.
@MainActor
final class CaptureFixture {
    private var gates: [CaptureGate] = []
    private var joins: [Task<Void, Never>] = []
    private var cancellations: [() -> Void] = []
    func gate() -> CaptureGate {
        let gate = CaptureGate()
        gates.append(gate)
        return gate
    }
    @discardableResult
    func track<Value: Sendable, Failure: Error>(_ task: Task<Value, Failure>) -> Task<Value, Failure> {
        cancellations.append { task.cancel() }
        joins.append(Task { _ = await task.result })
        return task
    }
    func releaseAll() { gates.forEach { $0.open() } }
    func cleanUp() async {
        releaseAll()
        cancellations.forEach { $0() }
        for join in joins { await join.value }
    }
}

@MainActor
func withCaptureFixture(_ body: (CaptureFixture) async throws -> Void) async throws {
    let fixture = CaptureFixture()
    do {
        try await body(fixture)
        await fixture.cleanUp()
    } catch {
        await fixture.cleanUp()
        throw error
    }
}

@available(iOS 26.0, macOS 26.0, *)
@MainActor
final class ControlledCaptureStream: ScreenCaptureStream {
    var starts = 0
    var stops = 0
    var capturing = false
    var startEntered: CaptureGate?
    var startRelease: CaptureGate?
    var stopEntered: CaptureGate?
    var stopRelease: CaptureGate?
    var startError: Error?

    func startCapture() async throws {
        starts += 1
        startEntered?.open()
        try await startRelease?.wait()
        if let startError { throw startError }
        capturing = true
    }
    func stopCapture() async throws {
        stops += 1
        stopEntered?.open()
        try await stopRelease?.wait()
        capturing = false
    }
}
