import Foundation
import AVFoundation
import Speech

// swiftlint:disable file_length

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

    /// Marks the start of a new stream generation and returns its identifier.
    ///
    /// Termination handlers capture the generation so that a handler firing late (after the
    /// session moved on to another stream) cannot tear down state it no longer owns.
    func beginStreamGeneration() -> Int {
        sessionGeneration &+= 1
        return sessionGeneration
    }

    /// Tear down the session in response to the consumer's stream terminating.
    ///
    /// Runs only when the terminating stream is still the current one; stale handlers
    /// (from streams that were already replaced or finished) are ignored.
    func handleStreamTermination(generation: Int) async {
        guard generation == sessionGeneration else { return }
        prepareForStop()
        await cleanup(cancelRecognizer: true, generation: generation)
        await finishStream(error: nil, generation: generation)
    }

    var isPausableStreamingMode: Bool {
        streamingMode == .liveMicrophone || streamingMode == .screenCapture
    }

    func startSpeechPipeline(
        with streamContinuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation,
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil,
        generation: Int
    ) async {
        do {
            if Self.shouldLog(.notice) {
                Self.logger.notice("Starting pipeline setup")
            }
            try Task.checkCancellation()
            try await ensurePermissions()
            try Task.checkCancellation()
            try await setupAudioSession()
            try Task.checkCancellation()

            let shouldUseNativeCapture = shouldUseNativeCaptureInputProvider
            let transcriber = try await setUpSpeechTranscriber(
                contextualStrings: contextualStrings,
                startAnalyzerImmediately: !shouldUseNativeCapture
            )
            try Task.checkCancellation()
            if Self.shouldLog(.info) {
                Self.logger.info("Transcriber prepared with modules")
            }

            recognizerTask = createSpeechRecognizerTask(
                transcriber: transcriber,
                streamContinuation: streamContinuation,
                generation: generation
            )

            if !(try await setUpNativeCaptureStreamingIfAvailable(generation: generation)) {
                try Task.checkCancellation()
                try startAudioStreaming()
            }
            try Task.checkCancellation()

            streamingMode = .liveMicrophone
            setStatus(.transcribing)
            activeResultKind = .speech
            if Self.shouldLog(.info) {
                Self.logger.info("Pipeline started (mode: live microphone)")
            }
        } catch is CancellationError {
            pipelineTask = nil
            await finishCancelledPipelineSetup(generation: generation)
        } catch {
            if Self.shouldLog(.error) {
                Self.logger.error("Pipeline setup failed: \(error.localizedDescription, privacy: .public)")
            }
            pipelineTask = nil
            await finishWithStartupError(error, generation: generation)
        }
    }

    func startDictationPipeline(
        with streamContinuation: AsyncThrowingStream<DictationTranscriber.Result, Error>.Continuation,
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil,
        generation: Int
    ) async {
        do {
            if Self.shouldLog(.notice) {
                Self.logger.notice("Starting dictation pipeline setup")
            }
            try Task.checkCancellation()
            try await ensurePermissions()
            try Task.checkCancellation()
            try await setupAudioSession()
            try Task.checkCancellation()

            let shouldUseNativeCapture = shouldUseNativeCaptureInputProvider
            let transcriber = try await setUpDictationTranscriber(
                contextualStrings: contextualStrings,
                startAnalyzerImmediately: !shouldUseNativeCapture
            )
            try Task.checkCancellation()
            if Self.shouldLog(.info) {
                Self.logger.info("Dictation transcriber prepared with modules")
            }

            recognizerTask = createDictationRecognizerTask(
                transcriber: transcriber,
                streamContinuation: streamContinuation,
                generation: generation
            )

            if !(try await setUpNativeCaptureStreamingIfAvailable(generation: generation)) {
                try Task.checkCancellation()
                try startAudioStreaming()
            }
            try Task.checkCancellation()

            streamingMode = .liveMicrophone
            setStatus(.transcribing)
            activeResultKind = .dictation
            if Self.shouldLog(.info) {
                Self.logger.info("Dictation pipeline started (mode: live microphone)")
            }
        } catch is CancellationError {
            pipelineTask = nil
            await finishCancelledPipelineSetup(generation: generation)
        } catch {
            if Self.shouldLog(.error) {
                Self.logger.error("Dictation pipeline setup failed: \(error.localizedDescription, privacy: .public)")
            }
            pipelineTask = nil
            await finishWithStartupError(error, generation: generation)
        }
    }

    /// Unwind a pipeline whose setup task was cancelled by `cleanup` (stop or stream termination).
    ///
    /// The canceller already ran `cleanup`, but this task may have created additional state
    /// (transcriber, analyzer, audio taps) after that cleanup finished, so run it once more.
    /// `finishStream` is a no-op when the canceller already finished the stream, and both steps
    /// are skipped when a newer stream generation owns the session state.
    func finishCancelledPipelineSetup(generation: Int) async {
        guard generation == sessionGeneration else { return }
        if Self.shouldLog(.debug) {
            Self.logger.debug("Pipeline setup cancelled; unwinding")
        }
        await cleanup(cancelRecognizer: true, generation: generation)
        guard generation == sessionGeneration else { return }
        await finishStream(error: nil, generation: generation)
    }

    func finishWithStartupError(_ error: Error, generation: Int) async {
        guard generation == sessionGeneration else { return }
        // A cancelled setup task means another teardown already owns the stream; unwind
        // quietly instead of surfacing a spurious error to a stream that was stopped on purpose.
        if Task.isCancelled {
            await finishCancelledPipelineSetup(generation: generation)
            return
        }
        if Self.shouldLog(.error) {
            Self.logger.error("Finishing due to startup error: \(error.localizedDescription, privacy: .public)")
        }
        prepareForStop()
        await cleanup(cancelRecognizer: true, generation: generation)
        await finishStream(error: error, generation: generation)
    }

    func finishFromRecognizerTask(error: Error?, generation: Int) async {
        guard generation == sessionGeneration else { return }
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
        await cleanup(cancelRecognizer: false, generation: generation)
        await finishStream(error: error, generation: generation)
    }

    /// Tear down the active pipeline.
    ///
    /// All session state is detached synchronously up front so that concurrent teardowns (or a
    /// new session starting once the stream finishes) never observe partially-cleared state; the
    /// slow finalization steps then operate on the detached references. Steps that touch shared
    /// state after a suspension re-check `generation` so a stale teardown cannot damage a newer
    /// session.
    func cleanup(cancelRecognizer: Bool, generation: Int) async {
        guard generation == sessionGeneration else { return }
        if Self.shouldLog(.debug) {
            Self.logger.debug("Cleanup started (cancelRecognizer: \(cancelRecognizer, privacy: .public))")
        }
        // Cancel any in-flight pipeline setup so it cannot re-arm audio after this cleanup.
        // Harmless when cleanup runs from within that task (the flag is simply never observed).
        let setupTask = pipelineTask
        pipelineTask = nil
        setupTask?.cancel()

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
        tearDownNativeCaptureStreaming()
        deactivateAudioSessionIfNeeded()
#if os(iOS)
        shouldResumeAfterInterruption = false
#endif
        let detached = detachTranscriberState()
        await stopScreenCaptureStreamingIfNeeded()
        await finalizeDetachedTranscriberState(detached)

        guard generation == sessionGeneration else { return }
        await modelManager.releaseLocales()

        guard generation == sessionGeneration else { return }
        setStatus(.idle)
        if Self.shouldLog(.debug) {
            Self.logger.debug("Cleanup completed")
        }
    }

    /// Finish the active consumer stream.
    ///
    /// Generation-guarded so a teardown belonging to an older stream can never finish (or
    /// error out) the stream of a session that has since started.
    func finishStream(error: Error?, generation: Int) async {
        guard generation == sessionGeneration else { return }
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

    func createSpeechRecognizerTask(
        transcriber: SpeechTranscriber,
        streamContinuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation,
        generation: Int
    ) -> Task<Void, Never> {
        createRecognizerTask(
            label: "Recognizer task",
            results: transcriber.results,
            streamContinuation: streamContinuation,
            generation: generation
        )
    }

    private func createDictationRecognizerTask(
        transcriber: DictationTranscriber,
        streamContinuation: AsyncThrowingStream<DictationTranscriber.Result, Error>.Continuation,
        generation: Int
    ) -> Task<Void, Never> {
        createRecognizerTask(
            label: "Dictation recognizer task",
            results: transcriber.results,
            streamContinuation: streamContinuation,
            generation: generation
        )
    }

    private func createRecognizerTask<Sequence: AsyncSequence>(
        label: String,
        results: Sequence,
        streamContinuation: AsyncThrowingStream<Sequence.Element, Error>.Continuation,
        generation: Int
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
                await self.finishFromRecognizerTask(error: nil, generation: generation)
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
                await self.finishFromRecognizerTask(error: error, generation: generation)
            }
        }
    }
}
