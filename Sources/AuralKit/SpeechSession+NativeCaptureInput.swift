import Foundation
@preconcurrency import AVFoundation
import Speech

extension SpeechSession {
    var shouldUseNativeCaptureInputProvider: Bool {
#if swift(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *) {
            return inputProviderPreference == .automatic
        }
#endif
        return false
    }

    func setUpNativeCaptureStreamingIfAvailable() async throws -> Bool {
#if swift(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *), shouldUseNativeCaptureInputProvider {
            try await setUpNativeCaptureStreaming()
            return true
        }
#endif
        return false
    }

    func tearDownNativeCaptureStreaming() {
#if swift(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *) {
            tearDownNativeCaptureStreamingIfAvailable()
        }
#endif
    }
}

#if swift(>=6.4)
@available(iOS 27.0, macOS 27.0, *)
extension SpeechSession {
    private var canUseNativeCaptureInputProvider: Bool {
        inputProviderPreference == .automatic
    }

    func setUpNativeCaptureStreaming() async throws {
        guard !isAudioStreaming else {
            throw SpeechSessionError.recognitionStreamSetupFailed
        }
        guard canUseNativeCaptureInputProvider else {
            throw SpeechSessionError.recognitionStreamSetupFailed
        }
        guard let modules = activeModules, let analyzer else {
            throw SpeechSessionError.recognitionStreamSetupFailed
        }
        guard let captureDevice = AVCaptureDevice.default(for: .audio) else {
            throw SpeechSessionError.recognitionStreamSetupFailed
        }

        let provider = try await CaptureInputSequenceProvider.providerWithSession(
            from: captureDevice,
            compatibleWith: modules,
            priority: analyzerConfiguration.priority
        )
        nativeCaptureSession = provider.captureSession

        try await prepareAnalyzerForStartIfNeeded(in: nil)

        let analyzerInputs = provider.analyzerInputs
        nativeCaptureAnalysisTask = Task<Void, Never> { [weak self, analyzer, analyzerInputs] in
            do {
                let lastAudioTime = try await analyzer.analyzeSequence(analyzerInputs)
                if let lastAudioTime {
                    try await analyzer.finalizeAndFinish(through: lastAudioTime)
                } else {
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                }
            } catch is CancellationError {
                // Cancellation is expected during explicit cleanup.
            } catch {
                await self?.finishFromNativeCaptureAnalysis(error)
            }
        }
        startSpeechDetectorMonitoringIfNeeded()

        _ = startPreparedNativeCaptureStreaming()
    }

    func startPreparedNativeCaptureStreaming() -> Bool {
        guard let nativeCaptureSession else { return false }

        if Self.shouldLog(.debug) {
            Self.logger.debug("Starting native capture session")
        }
        nativeCaptureSession.startRunning()
        isAudioStreaming = true
        return true
    }

    func stopPreparedNativeCaptureStreaming() -> Bool {
        guard let nativeCaptureSession else { return false }

        if Self.shouldLog(.debug) {
            Self.logger.debug("Stopping native capture session")
        }
        nativeCaptureSession.stopRunning()
        isAudioStreaming = false
        return true
    }

    func tearDownNativeCaptureStreamingIfAvailable() {
        nativeCaptureAnalysisTask?.cancel()
        nativeCaptureAnalysisTask = nil
        if nativeCaptureSession != nil {
            _ = stopPreparedNativeCaptureStreaming()
        }
        nativeCaptureSession = nil
    }

    func finishFromNativeCaptureAnalysis(_ error: Error) async {
        nativeCaptureAnalysisTask = nil
        await finishFromRecognizerTask(error: error)
    }
}
#endif
