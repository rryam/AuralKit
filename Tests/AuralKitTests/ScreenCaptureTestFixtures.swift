import Foundation
@testable import AuralKit

enum CaptureFixtureError: Error { case deadline, startFailed }

@MainActor
final class CaptureGate {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() { (stream, continuation) = AsyncStream.makeStream() }

    func wait() async throws {
        try await awaitResult(timeout: 3) {
            for await _ in self.stream {}
            try Task.checkCancellation()
        }
    }

    func open() { continuation.finish() }
}

// Release suspended capture calls before joining tasks, including when an assertion fails.
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
    var stopError: Error?

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
        if let stopError { throw stopError }
        capturing = false
    }
}

@MainActor
func waitForCaptureState(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !predicate() {
        guard ContinuousClock.now < deadline else { throw CaptureFixtureError.deadline }
        try Task.checkCancellation()
        await Task.yield()
    }
}
