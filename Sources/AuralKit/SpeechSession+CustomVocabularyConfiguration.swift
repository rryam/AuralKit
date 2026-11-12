import Foundation
import Speech
import CryptoKit
import OSLog

@MainActor
extension SpeechSession {

    /// Configure the session's custom vocabulary, compiling assets as needed.
    ///
    /// Compiled files are temporary and remain available while the session or a native consumer uses them.
    /// Cancelling compilation waits for preparation to finish, then throws `CancellationError`
    /// without replacing the current configuration. Superseded compilation results are discarded.
    ///
    /// - Parameter vocabulary: The vocabulary descriptor to activate, or `nil` to clear the current
    ///   configuration.
    /// - Throws: A `SpeechSessionError` when the session is active, the descriptor locale mismatches, or
    ///   compilation fails.
    public func configureCustomVocabulary(_ vocabulary: CustomVocabulary?) async throws {
        if streamingMode != .inactive || continuation != nil || pipelineTask != nil || recognizerTask != nil {
            throw SpeechSessionError.customVocabularyRequiresIdleSession
        }

        guard let vocabulary else {
            clearCustomVocabularyArtifacts(removeDescriptor: true)
            return
        }

        let requestedLocale = vocabulary.locale.identifier(.bcp47)
        let sessionLocale = locale.identifier(.bcp47)
        guard requestedLocale == sessionLocale else {
            throw SpeechSessionError.customVocabularyUnsupportedLocale(vocabulary.locale)
        }

        let cacheKey: String
        do {
            cacheKey = try vocabulary.stableCacheKey()
        } catch {
            throw SpeechSessionError.customVocabularyCompilationFailed(error)
        }

        let requestID = UUID()
        customVocabularyRequestID = requestID
        try Task.checkCancellation()

        if cacheKey == customVocabularyCacheKey,
           customVocabularyConfiguration != nil {
            customVocabularyDescriptor = vocabulary
            return
        }

        // Offload compilation to background task to avoid blocking main actor UI
        // Capture compiler before detached task to avoid cross-actor access
        let compiler = customVocabularyCompiler
        let task = Task.detached(priority: .userInitiated) {
            try await compiler.compile(descriptor: vocabulary)
        }
        let compilation = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        // Rejected results release their private artifacts after the compiler has joined.
        try Task.checkCancellation()
        guard customVocabularyRequestID == requestID else { throw CancellationError() }
        guard streamingMode == .inactive, continuation == nil, pipelineTask == nil, recognizerTask == nil else {
            throw SpeechSessionError.customVocabularyRequiresIdleSession
        }

        customVocabularyDescriptor = vocabulary
        customVocabularyConfiguration = compilation.configuration
        customVocabularyCacheKey = compilation.cacheKey
        customVocabularyOutputDirectory = compilation.outputDirectory
        customVocabularyArtifacts = compilation.artifacts
    }

    /// Start a dictation-backed transcription stream that leverages the currently configured custom vocabulary.
    ///
    /// - Parameter contextualStrings: Optional contextual strings to bias recognition alongside the custom
    ///   language model.
    /// - Returns: An async throwing stream producing `DictationTranscriber.Result` values.
    public func startDictationTranscribing(
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) -> AsyncThrowingStream<DictationTranscriber.Result, Error> {
        let (stream, newContinuation) = AsyncThrowingStream<DictationTranscriber.Result, Error>.makeStream()

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

        setStatus(.preparing)
        continuation = .dictation(newContinuation)

        pipelineTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.startDictationPipeline(
                with: newContinuation,
                contextualStrings: contextualStrings,
                generation: generation
            )
        }

        return stream
    }

    /// Compile and activate the provided custom vocabulary, then begin dictation-backed transcription.
    ///
    /// - Parameters:
    ///   - customVocabulary: The descriptor describing phrases, pronunciations, and templates to prefer.
    ///   - contextualStrings: Optional contextual strings to further bias the transcription.
    /// - Returns: An async throwing stream emitting dictation transcriber results enriched by the custom vocabulary.
    /// - Throws: Errors encountered while configuring the vocabulary or starting the dictation pipeline.
    public func startTranscribing(
        customVocabulary: CustomVocabulary,
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) async throws -> AsyncThrowingStream<DictationTranscriber.Result, Error> {
        try await configureCustomVocabulary(customVocabulary)
        return startDictationTranscribing(contextualStrings: contextualStrings)
    }

    func clearCustomVocabularyArtifacts(removeDescriptor: Bool) {
        customVocabularyRequestID = nil
        // Dropping the session's owner cannot delete files retained by native consumers.
        customVocabularyArtifacts = nil

        customVocabularyConfiguration = nil
        customVocabularyCacheKey = nil
        customVocabularyOutputDirectory = nil

        if removeDescriptor {
            customVocabularyDescriptor = nil
        }
    }
}
