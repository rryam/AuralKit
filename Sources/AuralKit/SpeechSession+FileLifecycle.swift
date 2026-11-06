import Foundation

/// Owns the actual tasks for one file stream. Producers request retirement and
/// return; only the separate terminal task joins them, so none can join itself.
@MainActor
final class FileTranscriptionRun {
    private var setupTask: Task<Void, Never>?
    private var ingestionTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private(set) var terminalTask: Task<Void, Never>?
    private var stoppingInput = false
    private var terminalError: Error?
    private let finalize: @MainActor () async throws -> Void
    private let complete: @MainActor (Error?) async -> Void

    init(
        finalize: @escaping @MainActor () async throws -> Void,
        complete: @escaping @MainActor (Error?) async -> Void
    ) {
        self.finalize = finalize
        self.complete = complete
    }

    func startSetup(_ operation: @escaping @MainActor () async throws -> Void) {
        precondition(setupTask == nil)
        setupTask = Task {
            do {
                try Task.checkCancellation()
                try await operation()
            } catch {
                requestRetirement(error: error)
            }
        }
    }

    func startIngestion(_ operation: @escaping @MainActor () async throws -> Bool) {
        precondition(ingestionTask == nil)
        ingestionTask = Task {
            do {
                try Task.checkCancellation()
                let completed = try await operation()
                try Task.checkCancellation()
                guard completed else {
                    throw SpeechSessionError.audioFileReadFailed(CocoaError(
                        .fileReadUnknown,
                        userInfo: [NSLocalizedDescriptionKey: "Audio input ended before all declared frames were read."]
                    ))
                }
            } catch {
                requestRetirement(error: error)
            }
        }
        // Setup can install a child after stop has already latched retirement.
        if stoppingInput { ingestionTask?.cancel() }
    }

    func startResults<Sequence: AsyncSequence>(
        _ results: Sequence,
        yield: @escaping @MainActor (Sequence.Element) -> Void
    ) where Sequence: Sendable, Sequence.Element: Sendable {
        precondition(resultTask == nil)
        resultTask = Task {
            do {
                for try await result in results {
                    yield(result)
                }
                try Task.checkCancellation()
                requestRetirement(cancelInput: false)
            } catch {
                requestRetirement(error: error)
            }
        }
    }

    /// Latch synchronously before any suspension. Concurrent callers receive
    /// the same work, including callers arriving during finalization/drain.
    @discardableResult
    func requestRetirement(error: Error? = nil, cancelInput: Bool = true) -> Task<Void, Never> {
        if let terminalTask {
            if !stoppingInput, cancelInput {
                terminalError = error
                stoppingInput = true
                setupTask?.cancel()
                ingestionTask?.cancel()
            }
            return terminalTask
        }
        terminalError = error
        stoppingInput = cancelInput
        if cancelInput {
            setupTask?.cancel()
            ingestionTask?.cancel()
        }
        let terminal = Task {
            await setupTask?.value
            if stoppingInput { ingestionTask?.cancel() }
            await ingestionTask?.value
            // Keep results alive while finalization publishes its last chunks.
            do {
                try await finalize()
            } catch {
                if terminalError == nil { terminalError = error }
                resultTask?.cancel()
            }
            await resultTask?.value
            await complete(terminalError)
            setupTask = nil
            ingestionTask = nil
            resultTask = nil
        }
        terminalTask = terminal
        return terminal
    }
}
