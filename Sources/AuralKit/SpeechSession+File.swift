import Foundation
import AVFoundation
import Speech

/// Configuration used by `SpeechSession` when transcribing an audio file from disk.
public struct FileTranscriptionOptions {
    /// Optional contextual strings to improve transcription accuracy.
    public var contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]?

    /// Maximum allowed duration for the audio file. Files longer than this will fail validation.
    public var maxDuration: TimeInterval?

    /// Directories considered safe for audio file reads. Defaults to the app sandbox directories.
    public var allowedDirectories: [URL]

    /// Creates a new set of file transcription options.
    /// - Parameters:
    ///   - contextualStrings: Tag-keyed terms that bias recognition toward domain-specific vocabulary.
    ///   - maxDuration: Upper limit for the audio length; longer files trigger `.audioFileTooLong`.
    ///   - allowedDirectories: Whitelisted directories that file URLs must reside in after resolving symlinks.
    public init(
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil,
        maxDuration: TimeInterval? = nil,
        allowedDirectories: [URL]? = nil
    ) {
        self.contextualStrings = contextualStrings
        self.maxDuration = maxDuration
        self.allowedDirectories = FileTranscriptionOptions.prepareAllowedDirectories(allowedDirectories)
    }

    private static func prepareAllowedDirectories(_ directories: [URL]?) -> [URL] {
        let fileManager = FileManager.default
        var resolved = directories?.filter(\.isFileURL) ?? []

        if resolved.isEmpty {
            resolved.append(contentsOf: fileManager.urls(for: .documentDirectory, in: .userDomainMask))
            resolved.append(contentsOf: fileManager.urls(for: .cachesDirectory, in: .userDomainMask))
            resolved.append(contentsOf: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask))
            resolved.append(fileManager.temporaryDirectory)
            resolved.append(URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
            #if os(macOS)
            resolved.append(fileManager.homeDirectoryForCurrentUser)
            #endif
        }

        var unique: [String: URL] = [:]
        for directory in resolved {
            let sanitized = directory.standardizedFileURL.resolvingSymlinksInPath()
            unique[sanitized.path] = sanitized
        }
        return Array(unique.values)
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
        startFileTranscription { session, continuation, generation in
            await session.startFilePipeline(
                with: continuation,
                audioFileURL: audioFile,
                options: options,
                progressHandler: progressHandler,
                generation: generation
            )
        }
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
    ) async throws -> [SpeechTranscriber.Result] {
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

        return finalResults
    }
}

// MARK: - Private helpers

private extension SpeechSession {
    func startFilePipeline(
        with streamContinuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation,
        audioFileURL: URL,
        options: FileTranscriptionOptions,
        progressHandler: (@Sendable (Double) -> Void)?,
        generation: Int
    ) async {
        do {
            try Task.checkCancellation()
            let validation = try validateAudioFile(at: audioFileURL, options: options)
            try await ensureSpeechRecognitionAuthorization(context: "for file transcription")
            try Task.checkCancellation()
            let shouldUseNativeAnalyzer = shouldUseNativeFileAnalyzer(progressHandler: progressHandler)
            try await setUpFilePipeline(
                with: streamContinuation,
                contextualStrings: options.contextualStrings,
                startAnalyzerImmediately: !shouldUseNativeAnalyzer,
                generation: generation
            )
            try Task.checkCancellation()
            startFileIngestion(generation: generation) { session in
                let completed = try await session.feedAudioFile(
                    validation, progressHandler: progressHandler, generation: generation
                )
                if completed, let progressHandler {
                    session.reportFileProgress(1.0, handler: progressHandler, generation: generation)
                }
            }
        } catch is CancellationError {
            await finishFailedPipelineSetup(CancellationError(), generation: generation)
        } catch {
            if Self.shouldLog(.error) {
                Self.logger.error("File transcription pipeline failed: \(error.localizedDescription, privacy: .public)")
            }
            await finishFailedPipelineSetup(error, generation: generation)
        }
    }

    func validateAudioFile(
        at url: URL,
        options: FileTranscriptionOptions
    ) throws -> (file: AVAudioFile, totalFrames: AVAudioFramePosition) {
        let safeURL = try sanitizeAudioFileURL(
            url,
            allowedDirectories: options.allowedDirectories
        )

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: safeURL)
        } catch {
            throw SpeechSessionError.audioFileReadFailed(error)
        }

        audioFile.framePosition = 0

        let totalFrames = audioFile.length
        guard totalFrames > 0 else {
            let description = String(describing: audioFile.fileFormat.settings)
            throw SpeechSessionError.audioFileUnsupportedFormat(description)
        }

        if let maxDuration = options.maxDuration {
            let duration = Double(totalFrames) / audioFile.processingFormat.sampleRate
            if duration > maxDuration {
                throw SpeechSessionError.audioFileTooLong(maximum: maxDuration, actual: duration)
            }
        }

        return (audioFile, totalFrames)
    }
}

extension SpeechSession {
    func sanitizeAudioFileURL(
        _ url: URL,
        allowedDirectories: [URL]
    ) throws -> URL {
        guard url.isFileURL else {
            throw SpeechSessionError.audioFileInvalidURL(url)
        }

        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        let targetComponents = standardized.pathComponents
        let allowedComponentSets = allowedDirectories
            .map { $0.standardizedFileURL.resolvingSymlinksInPath().pathComponents }

        guard FileManager.default.fileExists(atPath: standardized.path) else {
            throw SpeechSessionError.audioFileNotFound(standardized)
        }

        let isWithinAllowedDirectory = allowedComponentSets.contains { allowedComponents in
            guard allowedComponents.count <= targetComponents.count else { return false }
            return targetComponents.starts(with: allowedComponents)
        }

        guard isWithinAllowedDirectory else {
            throw SpeechSessionError.audioFileOutsideAllowedDirectories(standardized)
        }

        return standardized
    }

    func setUpFilePipeline(
        with streamContinuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation,
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]?,
        startAnalyzerImmediately: Bool,
        mode: StreamingMode = .filePlayback,
        generation: Int
    ) async throws {
        if Self.shouldLog(.notice) {
            Self.logger.notice("Starting file transcription pipeline")
        }

        let transcriber = try await setUpSpeechTranscriber(
            contextualStrings: contextualStrings,
            startAnalyzerImmediately: startAnalyzerImmediately
        )
        try Task.checkCancellation()
        activeResultKind = .speech

        recognizerTask = createSpeechRecognizerTask(
            transcriber: transcriber,
            streamContinuation: streamContinuation,
            generation: generation
        )

        streamingMode = mode
        setStatus(.transcribing)
        if Self.shouldLog(.info) {
            Self.logger.info("File transcription pipeline active (mode: file playback)")
        }
    }
}

private extension SpeechSession {
    nonisolated func feedAudioFile(
        _ payload: (file: AVAudioFile, totalFrames: AVAudioFramePosition),
        progressHandler: (@Sendable (Double) -> Void)?,
        generation: Int
    ) async throws -> Bool {
#if swift(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *),
           progressHandler == nil,
           await shouldUseNativeAssetInputProvider {
            return try await feedAudioFileWithNativeAnalyzer(payload.file, progressHandler: progressHandler)
        }
#endif

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

            let framesToRead = AVAudioFrameCount(min(Int64(frameCapacity), totalFrames - processedFrames))

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

            let sendableBuffer = SendablePCMBuffer(buffer: bufferCopy)

            try await self.processAudioBuffer(sendableBuffer)

            processedFrames += AVAudioFramePosition(buffer.frameLength)

            if let progressHandler, totalFrames > 0 {
                let progress = min(1.0, max(0.0, Double(processedFrames) / Double(totalFrames)))
                await reportFileProgress(progress, handler: progressHandler, generation: generation)
            }
        }

        guard !Task.isCancelled else { return false }

        try await self.finishAnalyzerInput()

        return !Task.isCancelled && processedFrames >= totalFrames
    }

    func shouldUseNativeFileAnalyzer(progressHandler: (@Sendable (Double) -> Void)?) -> Bool {
#if swift(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *) {
            return inputProviderPreference == .automatic && progressHandler == nil
        }
#endif
        return false
    }
}

extension SpeechSession {
    typealias FileResultContinuation = AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation

    func startFileTranscription(
        mode: StreamingMode = .filePlayback,
        _ setup: @escaping @MainActor (SpeechSession, FileResultContinuation, Int) async -> Void
    ) -> AsyncThrowingStream<SpeechTranscriber.Result, Error> {
        let (stream, newContinuation) = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()
        guard continuation == nil, recognizerTask == nil, streamingMode == .inactive else {
            newContinuation.finish(throwing: SpeechSessionError.recognitionStreamSetupFailed)
            return stream
        }

        let generation = beginStreamGeneration()
        newContinuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleStreamTermination(generation: generation)
            }
        }
        if mode == .mediaPlayback { streamingMode = mode }
        setStatus(.preparing)
        continuation = .speech(newContinuation)
        pipelineTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await setup(self, newContinuation, generation)
        }
        return stream
    }

    func startFileIngestion(
        generation: Int,
        _ ingest: @escaping @MainActor (SpeechSession) async throws -> Void
    ) {
        fileIngestionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await ingest(self)
            } catch is CancellationError {
                // Cleanup cancelled the ingestion task.
            } catch {
                await finishWithStartupError(error, generation: generation)
            }
        }
    }

    func reportFileProgress(
        _ progress: Double,
        handler: @Sendable (Double) -> Void,
        generation: Int
    ) {
        guard !Task.isCancelled, generation == sessionGeneration,
              streamingMode == .filePlayback, status == .transcribing else { return }
        handler(progress)
    }
}
