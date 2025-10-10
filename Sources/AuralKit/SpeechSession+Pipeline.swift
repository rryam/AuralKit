import Foundation
import AVFoundation
import Speech

@MainActor
extension SpeechSession {

    // MARK: - Pipeline Orchestration

    func startPipeline(
        with streamContinuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation,
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) async {
        do {
            try await permissionsManager.ensurePermissions()

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

            recognizerTask = Task<Void, Never> { [weak self] in
                guard let self else { return }

                do {
                    for try await result in transcriber.results {
                        streamContinuation.yield(result)
                    }
                    await self.finishFromRecognizerTask(error: nil)
                } catch is CancellationError {
                    // Cancellation handled by cleanup logic
                } catch {
                    await self.finishFromRecognizerTask(error: error)
                }
            }

            try startAudioStreaming()

            streamingActive = true
            setStatus(.transcribing)
        } catch {
            await finishWithStartupError(error)
        }
    }

    func finishWithStartupError(_ error: Error) async {
        prepareForStop()
        await cleanup(cancelRecognizer: true)
        await finishStream(error: error)
    }

    func finishFromRecognizerTask(error: Error?) async {
        prepareForStop()
        await cleanup(cancelRecognizer: false)
        await finishStream(error: error)
    }

    func cleanup(cancelRecognizer: Bool) async {
        let task = recognizerTask
        recognizerTask = nil

        if cancelRecognizer {
            task?.cancel()
        }

        streamingActive = false
        stopAudioStreaming()
        await stopTranscriberAndCleanup()
        setStatus(.idle)
    }

    func finishStream(error: Error?) async {
        guard let cont = continuation else { return }
        continuation = nil

        if let error {
            cont.finish(throwing: error)
        } else {
            cont.finish()
        }
    }
}
