import Foundation

enum TestTimeoutError: LocalizedError {
    case timedOut(seconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case let .timedOut(seconds):
            return "Timed out waiting for async result after \(seconds)s"
        }
    }
}

final class AsyncStreamProbe<Element: Sendable>: @unchecked Sendable {
    private var iterator: AsyncStream<Element>.Iterator

    init(_ stream: AsyncStream<Element>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async -> Element? {
        await iterator.next()
    }
}

@MainActor
func awaitResult<T: Sendable>(
    timeout seconds: TimeInterval = 1.0,
    operation: @escaping @MainActor () async throws -> T
) async throws -> T {
    let nanoseconds = UInt64(seconds * 1_000_000_000)

    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: nanoseconds)
            throw TestTimeoutError.timedOut(seconds: seconds)
        }

        defer { group.cancelAll() }
        guard let value = try await group.next() else {
            fatalError("Timeout helper started without any tasks")
        }

        return value
    }
}

// Cancellation must reach the actual task, not just the child awaiting its value.
// The task must cooperate with cancellation; this helper still joins its completion.
@MainActor
func awaitResult<T: Sendable>(
    timeout seconds: TimeInterval = 1.0,
    task: Task<T, Never>
) async throws -> T {
    try await awaitResult(timeout: seconds) {
        try await withTaskCancellationHandler {
            let value = await task.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            task.cancel()
        }
    }
}

@MainActor
func withOwnedTasks<T: Sendable, Result>(
    _ tasks: [Task<T, Never>],
    operation: @MainActor () async throws -> Result
) async rethrows -> Result {
    do {
        let result = try await operation()
        for task in tasks { task.cancel() }
        for task in tasks { _ = await task.value }
        return result
    } catch {
        for task in tasks { task.cancel() }
        for task in tasks { _ = await task.value }
        throw error
    }
}
