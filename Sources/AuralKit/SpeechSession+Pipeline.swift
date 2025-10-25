import Foundation
@preconcurrency import AVFoundation
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

    func startSpeechPipeline(
        with streamContinuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation,
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) async {
        do {
            if Self.shouldLog(.notice) {
                Self.logger.notice("Starting pipeline setup")
            }
            try await ensurePermissions()
            try await setupAudioSession()

            let transcriber = try await setUpSpeechTranscriber(contextualStrings: contextualStrings)
            if Self.shouldLog(.info) {
                Self.logger.info("Transcriber prepared with modules")
            }

            recognizerTask = createSpeechRecognizerTask(
                transcriber: transcriber,
                streamContinuation: streamContinuation
            )

            try startAudioStreaming()

            streamingMode = .liveMicrophone
            setStatus(.transcribing)
            activeResultKind = .speech
            if Self.shouldLog(.info) {
                Self.logger.info("Pipeline started (mode: live microphone)")
            }
        } catch {
            if Self.shouldLog(.error) {
                Self.logger.error("Pipeline setup failed: \(error.localizedDescription, privacy: .public)")
            }
            await finishWithStartupError(error)
        }
    }

    func startDictationPipeline(
        with streamContinuation: AsyncThrowingStream<DictationTranscriber.Result, Error>.Continuation,
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) async {
        do {
            if Self.shouldLog(.notice) {
                Self.logger.notice("Starting dictation pipeline setup")
            }
            try await ensurePermissions()
            try await setupAudioSession()

            let transcriber = try await setUpDictationTranscriber(contextualStrings: contextualStrings)
            if Self.shouldLog(.info) {
                Self.logger.info("Dictation transcriber prepared with modules")
            }

            recognizerTask = createDictationRecognizerTask(
                transcriber: transcriber,
                streamContinuation: streamContinuation
            )

            try startAudioStreaming()

            streamingMode = .liveMicrophone
            setStatus(.transcribing)
            activeResultKind = .dictation
            if Self.shouldLog(.info) {
                Self.logger.info("Dictation pipeline started (mode: live microphone)")
            }
        } catch {
            if Self.shouldLog(.error) {
                Self.logger.error("Dictation pipeline setup failed: \(error.localizedDescription, privacy: .public)")
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
                Self.logger.error(
                    "Finishing from recognizer with error: \(error.localizedDescription, privacy: .public)"
                )
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

        streamingMode = .inactive
        activeResultKind = nil
        stopAudioStreaming()
        deactivateAudioSessionIfNeeded()
#if os(iOS)
        shouldResumeAfterInterruption = false
#endif
        await stopTranscriberAndCleanup()
        setStatus(.idle)
        if Self.shouldLog(.debug) {
            Self.logger.debug("Cleanup completed")
        }
    }

    func finishStream(error: Error?) async {
        guard let continuation else { return }
        self.continuation = nil

        switch continuation {
        case .speech(let speechContinuation):
            if let error {
                if Self.shouldLog(.error) {
                    Self.logger.error(
                        "Finishing stream with error: \(error.localizedDescription, privacy: .public)"
                    )
                }
                speechContinuation.finish(throwing: error)
            } else {
                if Self.shouldLog(.notice) {
                    Self.logger.notice("Finishing stream successfully")
                }
                speechContinuation.finish()
            }
        case .dictation(let dictationContinuation):
            if let error {
                if Self.shouldLog(.error) {
                    Self.logger.error(
                        "Finishing dictation stream with error: \(error.localizedDescription, privacy: .public)"
                    )
                }
                dictationContinuation.finish(throwing: error)
            } else {
                if Self.shouldLog(.notice) {
                    Self.logger.notice("Finishing dictation stream successfully")
                }
                dictationContinuation.finish()
            }
        }
    }

    // MARK: - Helper Methods

    func setupAudioSession() async throws {
#if os(iOS)
        try await MainActor.run {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                audioConfig.category,
                mode: audioConfig.mode,
                options: audioConfig.options
            )
            try audioSession.setActive(true)
            isAudioSessionActive = true
        }
#endif
#if os(iOS) || os(macOS)
        publishCurrentAudioInputInfo()
#endif
    }

#if os(iOS)
    private func deactivateAudioSessionIfNeeded() {
        guard isAudioSessionActive else { return }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
            isAudioSessionActive = false
            if Self.shouldLog(.info) {
                Self.logger.info("Audio session deactivated")
            }
        } catch {
            if Self.shouldLog(.error) {
                Self.logger.error("Failed to deactivate audio session: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
#else
    private func deactivateAudioSessionIfNeeded() {}
#endif

    private func createSpeechRecognizerTask(
        transcriber: SpeechTranscriber,
        streamContinuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation
    ) -> Task<Void, Never> {
        createRecognizerTask(
            label: "Recognizer task",
            results: transcriber.results,
            streamContinuation: streamContinuation
        )
    }

    private func createDictationRecognizerTask(
        transcriber: DictationTranscriber,
        streamContinuation: AsyncThrowingStream<DictationTranscriber.Result, Error>.Continuation
    ) -> Task<Void, Never> {
        createRecognizerTask(
            label: "Dictation recognizer task",
            results: transcriber.results,
            streamContinuation: streamContinuation
        )
    }

    private func createRecognizerTask<Sequence: AsyncSequence>(
        label: String,
        results: Sequence,
        streamContinuation: AsyncThrowingStream<Sequence.Element, Error>.Continuation
    ) -> Task<Void, Never>
    where Sequence: Sendable, Sequence.Element: Sendable {
        Task<Void, Never> { [weak self] in
            guard let self else { return }

            do {
                for try await result in results {
                    streamContinuation.yield(result)
                }
                if Self.shouldLog(.notice) {
                    Self.logger.notice("\(label, privacy: .public) completed without error")
                }
                await self.finishFromRecognizerTask(error: nil)
            } catch is CancellationError {
                if Self.shouldLog(.debug) {
                    Self.logger.debug("\(label, privacy: .public) cancelled")
                }
            } catch {
                if Self.shouldLog(.error) {
                    Self.logger.error(
                        "\(label, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                await self.finishFromRecognizerTask(error: error)
            }
        }
    }
}
