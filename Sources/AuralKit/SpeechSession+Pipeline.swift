import Foundation
import AVFoundation
import Speech

@MainActor
extension SpeechSession {

    // MARK: - Permissions

    /// Check if all required permissions are granted
    func ensurePermissions() async throws {
        // Check microphone permission (iOS & macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            if Self.shouldLog(.info) {
                Self.logger.info("Microphone permission already authorized")
            }
        case .notDetermined:
            if Self.shouldLog(.notice) {
                Self.logger.notice("Requesting microphone permission")
            }
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                if Self.shouldLog(.error) {
                    Self.logger.error("Microphone permission denied")
                }
                throw SpeechSessionError.microphonePermissionDenied
            }
        default:
            if Self.shouldLog(.error) {
                Self.logger.error("Microphone permission unavailable")
            }
            throw SpeechSessionError.microphonePermissionDenied
        }

        try await ensureSpeechRecognitionAuthorization()
    }

    func ensureSpeechRecognitionAuthorization(context: String? = nil) async throws {
        let suffix = context.map { " \($0)" } ?? ""

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            if Self.shouldLog(.info) {
                Self.logger.info("Speech recognition permission already authorized\(suffix)")
            }
            return
        case .notDetermined:
            if Self.shouldLog(.notice) {
                Self.logger.notice("Requesting speech recognition permission\(suffix)")
            }
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            if !granted {
                if Self.shouldLog(.error) {
                    Self.logger.error("Speech recognition permission denied\(suffix)")
                }
                throw SpeechSessionError.speechRecognitionPermissionDenied
            }
        default:
            if Self.shouldLog(.error) {
                Self.logger.error("Speech recognition permission unavailable\(suffix)")
            }
            throw SpeechSessionError.speechRecognitionPermissionDenied
        }
    }

    // MARK: - Pipeline Orchestration

    func startPipeline(
        with streamContinuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation,
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) async {
        do {
            if Self.shouldLog(.notice) {
                Self.logger.notice("Starting pipeline setup")
            }
            try await ensurePermissions()

#if os(iOS)
            try await MainActor.run {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(audioConfig.category, mode: audioConfig.mode, options: audioConfig.options)
                try audioSession.setActive(true)
            }
#endif
#if os(iOS) || os(macOS)
            publishCurrentAudioInputInfo()
#endif

            let transcriber = try await setUpTranscriber(contextualStrings: contextualStrings)
            if Self.shouldLog(.info) {
                Self.logger.info("Transcriber prepared with modules")
            }

            recognizerTask = Task<Void, Never> { [weak self] in
                guard let self else { return }

                do {
                    for try await result in transcriber.results {
                        streamContinuation.yield(result)
                    }
                    if Self.shouldLog(.notice) {
                        Self.logger.notice("Recognizer task completed without error")
                    }
                    await self.finishFromRecognizerTask(error: nil)
                } catch is CancellationError {
                    if Self.shouldLog(.debug) {
                        Self.logger.debug("Recognizer task cancelled")
                    }
                    // Cancellation handled by cleanup logic
                } catch {
                    if Self.shouldLog(.error) {
                        Self.logger.error("Recognizer task failed: \(error.localizedDescription, privacy: .public)")
                    }
                    await self.finishFromRecognizerTask(error: error)
                }
            }

            try startAudioStreaming()

            streamingActive = true
            setStatus(.transcribing)
            if Self.shouldLog(.info) {
                Self.logger.info("Pipeline started and streaming active")
            }
        } catch {
            if Self.shouldLog(.error) {
                Self.logger.error("Pipeline setup failed: \(error.localizedDescription, privacy: .public)")
            }
            await finishWithStartupError(error)
        }
    }

    func finishWithStartupError(_ error: Error) async {
        if Self.shouldLog(.error) {
            Self.logger.error("Finishing due to startup error: \(error.localizedDescription, privacy: .public)")
        }
        prepareForStop()
        await cleanup(cancelRecognizer: true)
        await finishStream(error: error)
    }

    func finishFromRecognizerTask(error: Error?) async {
        if let error {
            if Self.shouldLog(.error) {
                Self.logger.error("Finishing from recognizer with error: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            if Self.shouldLog(.notice) {
                Self.logger.notice("Finishing from recognizer without error")
            }
        }
        prepareForStop()
        await cleanup(cancelRecognizer: false)
        await finishStream(error: error)
    }

    func cleanup(cancelRecognizer: Bool) async {
        if Self.shouldLog(.debug) {
            Self.logger.debug("Cleanup started (cancelRecognizer: \(cancelRecognizer, privacy: .public))")
        }
        let task = recognizerTask
        recognizerTask = nil

        let ingestionTask = fileIngestionTask
        fileIngestionTask = nil
        ingestionTask?.cancel()

        if cancelRecognizer {
            if Self.shouldLog(.debug) {
                Self.logger.debug("Cancelling recognizer task")
            }
            task?.cancel()
        }

        streamingActive = false
        stopAudioStreaming()
        await stopTranscriberAndCleanup()
        setStatus(.idle)
        if Self.shouldLog(.debug) {
            Self.logger.debug("Cleanup completed")
        }
    }

    func finishStream(error: Error?) async {
        guard let cont = continuation else { return }
        continuation = nil

        if let error {
            if Self.shouldLog(.error) {
                Self.logger.error("Finishing stream with error: \(error.localizedDescription, privacy: .public)")
            }
            cont.finish(throwing: error)
        } else {
            if Self.shouldLog(.notice) {
                Self.logger.notice("Finishing stream successfully")
            }
            cont.finish()
        }
    }
}
