import Foundation

/// Harness waits cooperate; simulated native operations explicitly opt out.
@MainActor
final class FileJoinGate {
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

@MainActor
final class FileJoinRecord {
    var events: [String] = []
    var values: [Int] = []
    var error: Error?
    var timedOut = false
    var readerWasCancelled = false
}
