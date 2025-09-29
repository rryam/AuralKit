import Foundation
import Speech
import AVFoundation

// MARK: - Speech Transcriber Manager

final class SpeechTranscriberManager: @unchecked Sendable {

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?

    private let modelManager = ModelManager()

    var downloadProgress: Progress? {
        modelManager.currentDownloadProgress
    }

    /// Set up the transcriber with the given locale
    func setUpTranscriber(locale: Locale) async throws -> SpeechTranscriber {
        transcriber = SpeechTranscriber(locale: locale,
                                        transcriptionOptions: [],
                                        reportingOptions: [.volatileResults, .alternativeTranscriptions],
                                        attributeOptions: [.audioTimeRange, .transcriptionConfidence])

        guard let transcriber else {
            throw SpeechSessionError.recognitionStreamSetupFailed
        }

        analyzer = SpeechAnalyzer(modules: [transcriber])

        try await modelManager.ensureModel(transcriber: transcriber, locale: locale)

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

        guard let inputSequence else { return transcriber }

        try await analyzer?.start(inputSequence: inputSequence)

        return transcriber
    }

    /// Stream audio buffer to the transcriber
    func streamAudioToTranscriber(_ buffer: AVAudioPCMBuffer, converter: BufferConverter) async throws {
        guard let inputBuilder, let analyzerFormat else {
            throw SpeechSessionError.invalidAudioDataType
        }

        let converted = try converter.convertBuffer(buffer, to: analyzerFormat)
        let input = AnalyzerInput(buffer: converted)

        inputBuilder.yield(input)
    }

    /// Process audio buffer synchronously (for use in callbacks)
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: BufferConverter) throws {
        guard let inputBuilder, let analyzerFormat else {
            throw SpeechSessionError.invalidAudioDataType
        }

        let converted = try converter.convertBuffer(buffer, to: analyzerFormat)
        let input = AnalyzerInput(buffer: converted)
        inputBuilder.yield(input)
    }

    /// Stop transcribing and clean up
    func stop() async {
        inputBuilder?.finish()
        
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            // Finalization failed, but we still need to clean up resources
            // Log for debugging but don't propagate since stop() is best-effort cleanup
        }

        await modelManager.releaseLocales()

        inputBuilder = nil
        inputSequence = nil
        analyzerFormat = nil
        analyzer = nil
        transcriber = nil
    }
}
