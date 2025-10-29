import Foundation
import Speech
import CryptoKit
import OSLog

@MainActor
extension SpeechSession {

    /// Configure the session's custom vocabulary, compiling assets as needed.
    ///
    /// - Parameter vocabulary: The vocabulary descriptor to activate, or `nil` to clear the current
    ///   configuration.
    /// - Throws: A `SpeechSessionError` when the session is active, the descriptor locale mismatches, or
    ///   compilation fails.
    public func configureCustomVocabulary(_ vocabulary: CustomVocabulary?) async throws {
        if streamingMode != .inactive {
            throw SpeechSessionError.customVocabularyRequiresIdleSession
        }

        guard let vocabulary else {
            await clearCustomVocabularyArtifacts(removeDescriptor: true)
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

        if cacheKey == customVocabularyCacheKey,
           customVocabularyConfiguration != nil {
            customVocabularyDescriptor = vocabulary
            return
        }

        let compilation = try await customVocabularyCompiler.compile(descriptor: vocabulary)

        if let previousDirectory = customVocabularyOutputDirectory,
           previousDirectory != compilation.outputDirectory {
            do {
                try FileManager.default.removeItem(at: previousDirectory)
            } catch {
                logCustomVocabularyError(
                    "Failed to delete previous vocabulary directory.",
                    path: previousDirectory.path,
                    error: error
                )
            }
        }

        customVocabularyDescriptor = vocabulary
        customVocabularyConfiguration = compilation.configuration
        customVocabularyCacheKey = compilation.cacheKey
        customVocabularyOutputDirectory = compilation.outputDirectory
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
        continuation = .dictation(newContinuation)

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.startDictationPipeline(with: newContinuation, contextualStrings: contextualStrings)
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

    func clearCustomVocabularyArtifacts(removeDescriptor: Bool) async {
        if let directory = customVocabularyOutputDirectory {
            // Best-effort cleanup of vocabulary directory
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                logCustomVocabularyError(
                    "Failed to delete vocabulary directory during cleanup.",
                    path: directory.path,
                    error: error
                )
            }
        }

        customVocabularyConfiguration = nil
        customVocabularyCacheKey = nil
        customVocabularyOutputDirectory = nil

        if removeDescriptor {
            customVocabularyDescriptor = nil
        }
    }
}
