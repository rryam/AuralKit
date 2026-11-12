import Foundation

@available(iOS 26.0, macOS 14.0, *)
@MainActor
protocol ScreenCaptureStream: AnyObject {
    func startCapture() async throws
    func stopCapture() async throws
}

@available(iOS 26.0, macOS 14.0, *)
@MainActor
struct ScreenCaptureResumeOutcome {
    let resolve: @MainActor () throws -> Bool
}

/// Serializes capture side effects across suspension. Admission changes intent immediately;
/// only internal operations are joined, never a public caller that may await session cleanup.
@available(iOS 26.0, macOS 14.0, *)
@MainActor
final class ScreenCaptureTransitions {
    enum DesiredState { case running, paused, stopped }
    private(set) var desiredState = DesiredState.running
    private(set) var stream: (any ScreenCaptureStream)?
    private(set) var isRunning = false
    private var revision = UUID()
    private var controlRevision = UUID()
    private var tail: Task<Void, Error>?

    // Synchronous admission returns the owned handle before any capture call can suspend.
    func replace(makeStream: @escaping @MainActor () throws -> any ScreenCaptureStream) -> Task<Void, Error> {
        guard desiredState != .stopped else { return Task { throw CancellationError() } }
        let admitted = UUID()
        revision = admitted
        return enqueue {
            do {
                guard self.desiredState != .stopped, self.revision == admitted else { return }
                try await self.stopCurrent()
                guard self.desiredState != .stopped, self.revision == admitted else { return }
                self.stream = try makeStream()
                try await self.startCurrent(revision: admitted)
            } catch {
                // A stale picker operation must not report failure against its successor.
                guard self.desiredState != .stopped, self.revision == admitted else { return }
                throw error
            }
        }
    }

    func pause() -> Task<Void, Error> {
        guard desiredState != .stopped else { return enqueue {} }
        controlRevision = UUID()
        desiredState = .paused
        return enqueue { try await self.stopCurrent() }
    }

    func resume() -> Task<ScreenCaptureResumeOutcome, Never> {
        let control = UUID()
        controlRevision = control
        desiredState = desiredState == .stopped ? .stopped : .running
        let admitted = revision
        let previous = tail
        let operation = Task { @MainActor in
            _ = try? await previous?.value
            let error: Error?
            do {
                try await self.startCurrent(revision: admitted)
                error = nil
            } catch let failure {
                error = failure
            }
            return ScreenCaptureResumeOutcome {
                guard self.desiredState == .running, self.controlRevision == control else { return false }
                // A new selection inherits run intent, but not the old selection's failure.
                if self.revision == admitted, let error { throw error }
                return true
            }
        }
        tail = Task { _ = await operation.value }
        return operation
    }

    func stop() -> Task<Void, Error> {
        controlRevision = UUID()
        desiredState = .stopped
        return enqueue {
            defer { self.stream = nil }
            try await self.stopCurrent()
        }
    }

    private func enqueue(_ body: @escaping @MainActor () async throws -> Void) -> Task<Void, Error> {
        let previous = tail
        let operation = Task { @MainActor in
            // Failure must not bypass the join or prevent a later terminal stop.
            _ = try? await previous?.value
            try await body()
        }
        tail = operation
        return operation
    }

    private func stopCurrent() async throws {
        guard isRunning, let stream else { return }
        try await stream.stopCapture()
        isRunning = false
    }

    private func startCurrent(revision admitted: UUID) async throws {
        guard desiredState == .running, revision == admitted, !isRunning, let stream else { return }
        try await stream.startCapture()
        // Nothing else can perform capture calls until this operation exits. Intent can
        // still change during start; compensate before allowing a queued operation to run.
        isRunning = true
        if desiredState != .running || revision != admitted {
            try await stopCurrent()
        }
    }
}
