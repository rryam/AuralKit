import Foundation
import Speech

@MainActor
extension SpeechSession {

    // MARK: - Voice Activation Detection Stream Management

    func prepareSpeechDetectorResultsStream(
        reportResults: Bool
    ) -> AsyncStream<SpeechDetector.Result>.Continuation? {
        guard reportResults else {
            tearDownSpeechDetectorStream()
            return nil
        }

        if let existing = speechDetectorResultsContinuation {
            return existing
        }

        let (stream, continuation) = AsyncStream<SpeechDetector.Result>.makeStream()
        speechDetectorResultsStream = stream
        speechDetectorResultsContinuation = continuation
        if Self.shouldLog(.debug) {
            Self.logger.debug("Prepared speech detector results stream")
        }
        return continuation
    }

    func tearDownSpeechDetectorStream() {
        speechDetectorResultsTask?.cancel()
        speechDetectorResultsTask = nil
        speechDetectorResultsContinuation?.finish()
        speechDetectorResultsContinuation = nil
        speechDetectorResultsStream = nil
        isSpeechDetected = true
        if Self.shouldLog(.debug) {
            Self.logger.debug("Speech detector stream torn down")
        }
    }

    func startSpeechDetectorMonitoring() {
        guard let detector = speechDetector else { return }

        speechDetectorResultsTask?.cancel()
        if Self.shouldLog(.debug) {
            Self.logger.debug("Starting speech detector monitoring")
        }
        speechDetectorResultsTask = Task<Void, Never> { [weak self] in
            guard let self else { return }
            do {
                for try await result in detector.results {
                    await MainActor.run {
                        self.handleSpeechDetectorResult(result)
                    }
                }
            } catch {
                let finalError = (error as? CancellationError) != nil ? nil : error
                await MainActor.run {
                    self.handleSpeechDetectorStreamCompletion(error: finalError)
                }
                return
            }

            await MainActor.run {
                self.handleSpeechDetectorStreamCompletion(error: nil)
            }
            if Self.shouldLog(.notice) {
                Self.logger.notice("Speech detector monitoring completed")
            }
        }
    }

    func handleSpeechDetectorResult(_ result: SpeechDetector.Result) {
        isSpeechDetected = result.speechDetected
        speechDetectorResultsContinuation?.yield(result)
        if Self.shouldLog(.debug) {
            Self.logger.debug(
                "Speech detector result: speechDetected=\(result.speechDetected, privacy: .public)"
            )
        }
    }

    func handleSpeechDetectorStreamCompletion(error: Error?) {
        defer { speechDetectorResultsTask = nil }

        if let continuation = speechDetectorResultsContinuation {
            continuation.finish()
        }

        speechDetectorResultsContinuation = nil
        speechDetectorResultsStream = nil
        isSpeechDetected = true

        if let error {
            if Self.shouldLog(.error) {
                Self.logger.error(
                    "Speech detector stream ended with error: \(error.localizedDescription, privacy: .public)"
                )
            }
        } else {
            if Self.shouldLog(.notice) {
                Self.logger.notice("Speech detector stream completed successfully")
            }
        }
    }
}
