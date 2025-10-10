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
            Self.log("Microphone permission already authorized", level: .info)
        case .notDetermined:
            Self.log("Requesting microphone permission", level: .notice)
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                Self.log("Microphone permission denied", level: .error)
                throw SpeechSessionError.microphonePermissionDenied
            }
        default:
            Self.log("Microphone permission unavailable", level: .error)
            throw SpeechSessionError.microphonePermissionDenied
        }

        // Check speech recognition permission
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            Self.log("Speech recognition permission already authorized", level: .info)
            return
        case .notDetermined:
            Self.log("Requesting speech recognition permission", level: .notice)
            let granted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            if !granted {
                Self.log("Speech recognition permission denied", level: .error)
                throw SpeechSessionError.speechRecognitionPermissionDenied
            }
        default:
            Self.log("Speech recognition permission unavailable", level: .error)
            throw SpeechSessionError.speechRecognitionPermissionDenied
        }
    }

    // MARK: - Pipeline Orchestration

    func startPipeline(
        with streamContinuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation,
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) async {
        do {
            Self.log("Starting pipeline setup", level: .notice)
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
            Self.log("Transcriber prepared with modules", level: .info)

            recognizerTask = Task<Void, Never> { [weak self] in
                guard let self else { return }

                do {
                    for try await result in transcriber.results {
                        streamContinuation.yield(result)
                    }
                    Self.log("Recognizer task completed without error", level: .notice)
                    await self.finishFromRecognizerTask(error: nil)
                } catch is CancellationError {
                    Self.log("Recognizer task cancelled", level: .debug)
                    // Cancellation handled by cleanup logic
                } catch {
                    Self.log("Recognizer task failed: \(error.localizedDescription)", level: .error)
                    await self.finishFromRecognizerTask(error: error)
                }
            }

            try startAudioStreaming()

            streamingActive = true
            setStatus(.transcribing)
            Self.log("Pipeline started and streaming active", level: .info)
        } catch {
            Self.log("Pipeline setup failed: \(error.localizedDescription)", level: .error)
            await finishWithStartupError(error)
        }
    }

    func finishWithStartupError(_ error: Error) async {
        Self.log("Finishing due to startup error: \(error.localizedDescription)", level: .error)
        prepareForStop()
        await cleanup(cancelRecognizer: true)
        await finishStream(error: error)
    }

    func finishFromRecognizerTask(error: Error?) async {
        if let error {
            Self.log("Finishing from recognizer with error: \(error.localizedDescription)", level: .error)
        } else {
            Self.log("Finishing from recognizer without error", level: .notice)
        }
        prepareForStop()
        await cleanup(cancelRecognizer: false)
        await finishStream(error: error)
    }

    func cleanup(cancelRecognizer: Bool) async {
        Self.log("Cleanup started (cancelRecognizer: \(cancelRecognizer))", level: .debug)
        let task = recognizerTask
        recognizerTask = nil

        if cancelRecognizer {
            Self.log("Cancelling recognizer task", level: .debug)
            task?.cancel()
        }

        streamingActive = false
        stopAudioStreaming()
        await stopTranscriberAndCleanup()
        setStatus(.idle)
        Self.log("Cleanup completed", level: .debug)
    }

    func finishStream(error: Error?) async {
        guard let cont = continuation else { return }
        continuation = nil

        if let error {
            Self.log("Finishing stream with error: \(error.localizedDescription)", level: .error)
            cont.finish(throwing: error)
        } else {
            Self.log("Finishing stream successfully", level: .notice)
            cont.finish()
        }
    }
}
