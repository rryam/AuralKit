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

        guard let value = try await group.next() else {
            fatalError("Timeout helper started without any tasks")
        }

        group.cancelAll()
        return value
    }
}
