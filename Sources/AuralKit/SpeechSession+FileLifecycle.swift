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
    private var inputFinalizationStarted = false
    private let finalize: @MainActor (Bool) async throws -> Void
    private let complete: @MainActor (Error?) async -> Void

    init(
        finalize: @escaping @MainActor (Bool) async throws -> Void,
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
                requestRetirement(error: error, ownerCancelled: Task.isCancelled)
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
                requestRetirement(error: error, ownerCancelled: Task.isCancelled)
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
                requestRetirement(error: error, ownerCancelled: Task.isCancelled)
            }
        }
    }

    /// Called at the actual normal-feed finalization boundary, before suspension.
    /// Even a failed attempt must not be repeated by terminal cleanup.
    func finishInput(_ operation: @MainActor () async throws -> Void) async throws {
        precondition(!inputFinalizationStarted)
        inputFinalizationStarted = true
        do {
            try await operation()
        } catch {
            record(error, ownerCancelled: Task.isCancelled)
            // A failed normal finalization cannot promise result EOF either.
            resultTask?.cancel()
            throw error
        }
    }

    private func record(_ error: Error?, ownerCancelled: Bool) {
        guard let error else { return }
        if error is CancellationError {
            if !ownerCancelled, terminalError == nil { terminalError = error }
        } else if terminalError == nil || terminalError is CancellationError {
            terminalError = error
        }
    }

    /// Latch synchronously before any suspension. Concurrent callers receive
    /// the same work, including callers arriving during finalization/drain.
    @discardableResult
    func requestRetirement(
        error: Error? = nil, cancelInput: Bool = true, ownerCancelled: Bool = false
    ) -> Task<Void, Never> {
        // Error priority is independent of the latch used to cancel producers.
        // A real failure supersedes cancellation, but never an earlier real failure.
        record(error, ownerCancelled: ownerCancelled)
        if cancelInput, !stoppingInput {
            stoppingInput = true
            setupTask?.cancel()
            ingestionTask?.cancel()
        }
        if let terminalTask { return terminalTask }
        let terminal = Task {
            await setupTask?.value
            if stoppingInput { ingestionTask?.cancel() }
            await ingestionTask?.value
            // Keep results alive while finalization publishes its last chunks.
            do {
                try await finalize(inputFinalizationStarted)
            } catch {
                record(error, ownerCancelled: false)
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
