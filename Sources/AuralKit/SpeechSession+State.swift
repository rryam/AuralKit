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
}
