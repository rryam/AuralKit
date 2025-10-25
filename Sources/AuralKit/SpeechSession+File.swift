import Foundation
@preconcurrency import AVFoundation
import Speech

/// Configuration used by `SpeechSession` when transcribing an audio file from disk.
public struct FileTranscriptionOptions {
    /// Optional contextual strings to improve transcription accuracy.
    public var contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]?

    /// Maximum allowed duration for the audio file. Files longer than this will fail validation.
    public var maxDuration: TimeInterval?

    /// Creates a new set of file transcription options.
    /// - Parameters:
    ///   - contextualStrings: Tag-keyed terms that bias recognition toward domain-specific vocabulary.
    ///   - maxDuration: Upper limit for the audio length; longer files trigger `.audioFileTooLong`.
    public init(
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil,
        maxDuration: TimeInterval? = nil
    ) {
        self.contextualStrings = contextualStrings
        self.maxDuration = maxDuration
    }
}

/// Aggregate container that surfaces the final results produced by file transcription.
public struct FileTranscriptionResult {
    /// Final `SpeechTranscriber.Result` entries emitted during transcription.
    public let finalResults: [SpeechTranscriber.Result]

    /// Creates a new file transcription result container.
    /// - Parameter finalResults: Ordered collection of final analyzer results.
    public init(finalResults: [SpeechTranscriber.Result]) {
        self.finalResults = finalResults
    }
}

@MainActor
public extension SpeechSession {
    /// Stream transcription results for an audio file from disk.
    ///
    /// - Parameters:
    ///   - audioFile: Location of the audio file to transcribe.
    ///   - options: Additional configuration such as contextual strings or duration limits.
    ///   - progressHandler: Optional closure invoked with progress (0...1) as the file is processed.
    /// - Returns: An async throwing stream emitting results as transcription progresses.
    func streamTranscription(
        from audioFile: URL,
        options: FileTranscriptionOptions = .init(),
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) -> AsyncThrowingStream<SpeechTranscriber.Result, Error> {
        let (stream, newContinuation) = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()

        newContinuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.cleanup(cancelRecognizer: true)
            }
        }

        guard continuation == nil, recognizerTask == nil, streamingMode == .inactive else {
            newContinuation.finish(throwing: SpeechSessionError.recognitionStreamSetupFailed)
            return stream
        }

        setStatus(.preparing)
        continuation = newContinuation

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.startFilePipeline(
                with: newContinuation,
                audioFileURL: audioFile,
                options: options,
                progressHandler: progressHandler
            )
        }

        return stream
    }

    /// Convenience wrapper that collects final results from file transcription.
    ///
    /// - Parameters:
    ///   - audioFile: Location of the audio file to transcribe.
    ///   - options: Additional configuration such as contextual strings or duration limits.
    ///   - progressHandler: Optional closure invoked with progress (0...1) as the file is processed.
    /// - Returns: Aggregated final results once transcription completes.
    /// - Throws: `SpeechSessionError` when validation or transcription fails.
    func transcribe(
        audioFile: URL,
        options: FileTranscriptionOptions = .init(),
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> FileTranscriptionResult {
        let stream = streamTranscription(
            from: audioFile,
            options: options,
            progressHandler: progressHandler
        )
        let accumulator: @Sendable (
            inout [SpeechTranscriber.Result],
            SpeechTranscriber.Result
        ) -> Void = { results, result in
            if result.isFinal {
                results.append(result)
            }
        }
        let finalResults = try await stream.reduce(into: [SpeechTranscriber.Result](), accumulator)

        return FileTranscriptionResult(finalResults: finalResults)
    }
}

// MARK: - Private helpers

private extension SpeechSession {
    func startFilePipeline(
        with streamContinuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation,
        audioFileURL: URL,
        options: FileTranscriptionOptions,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async {
        do {
            let validation = try validateAudioFile(at: audioFileURL, maxDuration: options.maxDuration)
            try await ensureSpeechRecognitionAuthorization(context: "for file transcription")
            try await setUpFilePipeline(
                with: streamContinuation,
                contextualStrings: options.contextualStrings
            )
            let handler = progressHandler
            fileIngestionTask = Task<Void, Never> { [weak self] in
                guard let self else { return }
                defer {
                    Task { @MainActor [weak self] in
                        self?.fileIngestionTask = nil
                    }
                }

                do {
                    let completed = try await self.feedAudioFile(validation, progressHandler: handler)

                    if completed, let handler {
                        await MainActor.run {
                            handler(1.0)
                        }
                    }
                } catch is CancellationError {
                    // Swallow cancellation triggered by cleanup.
                } catch {
                    await self.finishWithStartupError(error)
                }
            }
        } catch {
            if Self.shouldLog(.error) {
                Self.logger.error("File transcription pipeline failed: \(error.localizedDescription, privacy: .public)")
            }
            await finishWithStartupError(error)
        }
    }

    func validateAudioFile(
        at url: URL,
        maxDuration: TimeInterval?
    ) throws -> (file: AVAudioFile, totalFrames: AVAudioFramePosition) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SpeechSessionError.audioFileNotFound(url)
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw SpeechSessionError.audioFileReadFailed(error)
        }

        audioFile.framePosition = 0

        let totalFrames = audioFile.length
        guard totalFrames > 0 else {
            let description = String(describing: audioFile.fileFormat.settings)
            throw SpeechSessionError.audioFileUnsupportedFormat(description)
        }

        if let maxDuration {
            let duration = Double(totalFrames) / audioFile.processingFormat.sampleRate
            if duration > maxDuration {
                throw SpeechSessionError.audioFileTooLong(maximum: maxDuration, actual: duration)
            }
        }

        return (audioFile, totalFrames)
    }

    func setUpFilePipeline(
        with streamContinuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation,
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]?
    ) async throws {
        if Self.shouldLog(.notice) {
            Self.logger.notice("Starting file transcription pipeline")
        }

        let transcriber = try await setUpTranscriber(contextualStrings: contextualStrings)

        recognizerTask = Task<Void, Never> { [weak self] in
                guard let self else { return }

                do {
                    for try await result in transcriber.results {
                        streamContinuation.yield(result)
                    }
                    if Self.shouldLog(.notice) {
                        Self.logger.notice("File recognizer task completed without error")
                    }
                    await self.finishFromRecognizerTask(error: nil)
                } catch is CancellationError {
                    if Self.shouldLog(.debug) {
                        Self.logger.debug("File recognizer task cancelled")
                    }
                } catch {
                    if Self.shouldLog(.error) {
                        Self.logger.error(
                            "File recognizer task failed: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                    await self.finishFromRecognizerTask(error: error)
                }
        }

        streamingMode = .filePlayback
        setStatus(.transcribing)
        if Self.shouldLog(.info) {
            Self.logger.info("File transcription pipeline active (mode: file playback)")
        }
    }

    nonisolated func feedAudioFile(
        _ payload: (file: AVAudioFile, totalFrames: AVAudioFramePosition),
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> Bool {
        var processedFrames: AVAudioFramePosition = 0
        let frameCapacity: AVAudioFrameCount = 4096
        let file = payload.file
        let totalFrames = payload.totalFrames
        let format = file.processingFormat

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            throw SpeechSessionError.conversionBufferCreationFailed
        }

        while processedFrames < totalFrames {
            if Task.isCancelled { break }

            let framesRemaining = AVAudioFrameCount(totalFrames - processedFrames)
            let framesToRead = min(frameCapacity, framesRemaining)

            buffer.frameLength = framesToRead

            do {
                try file.read(into: buffer, frameCount: framesToRead)
            } catch {
                throw SpeechSessionError.audioFileReadFailed(error)
            }

            if buffer.frameLength == 0 {
                break
            }

            guard let bufferCopy = buffer.copy() as? AVAudioPCMBuffer else {
                throw SpeechSessionError.conversionBufferCreationFailed
            }

            try await MainActor.run {
                try self.processAudioBuffer(bufferCopy)
            }

            processedFrames += AVAudioFramePosition(buffer.frameLength)

            if let progressHandler, totalFrames > 0 {
                let progress = min(1.0, max(0.0, Double(processedFrames) / Double(totalFrames)))
                await MainActor.run {
                    progressHandler(progress)
                }
            }
        }

        await MainActor.run {
            self.inputBuilder?.finish()
        }

        return !Task.isCancelled && processedFrames >= totalFrames
    }

}
