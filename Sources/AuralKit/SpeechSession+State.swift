import Foundation

@MainActor
extension SpeechSession {
    /// Update the session status and emit changes when state transitions occur.
    func setStatus(_ newStatus: Status) {
        guard status != newStatus else { return }
        let previousStatus = status
        if Self.shouldLog(.notice) {
            let previousDescription = String(describing: previousStatus)
            let newDescription = String(describing: newStatus)
            Self.logger.notice(
                "Status transition: \(previousDescription, privacy: .public) -> \(newDescription, privacy: .public)"
            )
        }
        status = newStatus
        for continuation in statusContinuations.values {
            continuation.yield(newStatus)
        }
    }

    /// Prepare the session for teardown while ensuring consistent state transitions.
    func prepareForStop() {
        switch status {
        case .idle, .stopping:
            break
        default:
            if Self.shouldLog(.debug) {
                let currentDescription = String(describing: status)
                Self.logger.debug("Preparing for stop from status: \(currentDescription, privacy: .public)")
            }
            setStatus(.stopping)
        }
    }

    func finishStatusStreams() {
        for continuation in statusContinuations.values {
            continuation.finish()
        }
        statusContinuations.removeAll()
    }

    /// Pause capture without tearing down the analyzer pipeline.
    ///
    /// Safe to call only when the session is actively transcribing live audio (microphone or
    /// screen capture). Calls during file transcription or in any other state are ignored.
    public func pauseTranscribing() async {
        guard status == .transcribing, isPausableStreamingMode else { return }
        let generation = sessionGeneration
        if streamingMode == .screenCapture {
            await pauseScreenCaptureStreamingIfNeeded()
        } else {
            stopAudioStreaming()
        }
        // A paused capture call can finish after stop has published idle, even in the
        // same generation; it must not publish paused over that terminal status.
        guard generation == sessionGeneration, status == .transcribing, isPausableStreamingMode else { return }
        setStatus(.paused)
    }

    /// Resume a paused capture session.
    ///
    /// - Throws: `SpeechSessionError` if audio streaming cannot restart.
    public func resumeTranscribing() async throws {
        guard status == .paused, isPausableStreamingMode else { return }
        let generation = sessionGeneration
        do {
            if streamingMode == .screenCapture {
                let outcome = try await resumeScreenCaptureStreamingIfNeeded()
                guard outcome.isCurrent() else { return }
                if let error = outcome.error { throw error }
            } else {
                try startAudioStreaming()
            }
            // A late start may have compensated for stop while this caller was suspended.
            // Generation alone is insufficient until a successor actually begins.
            guard generation == sessionGeneration, status == .paused, isPausableStreamingMode else { return }
            setStatus(.transcribing)
        } catch {
            // A late failure belongs to the detached provider, not a successor session.
            guard generation == sessionGeneration, status == .paused, isPausableStreamingMode else { throw error }
            prepareForStop()
            await cleanup(cancelRecognizer: true, generation: generation)
            await finishStream(error: error, generation: generation)
            throw error
        }
    }
}
