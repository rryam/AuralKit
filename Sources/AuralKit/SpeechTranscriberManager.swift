import Foundation
import Speech
import AVFoundation

// MARK: - Speech Transcriber Manager

final class SpeechTranscriberManager {

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?

    private let modelManager = ModelManager()

    /// Set up the transcriber with the given locale
    func setUpTranscriber(locale: Locale) async throws -> SpeechTranscriber {
        transcriber = SpeechTranscriber(locale: locale,
                                        transcriptionOptions: [],
                                        reportingOptions: [.volatileResults],
                                        attributeOptions: [.audioTimeRange])

        guard let transcriber else {
            throw AuralKitError.recognitionStreamSetupFailed
        }

        analyzer = SpeechAnalyzer(modules: [transcriber])

        do {
            try await modelManager.ensureModel(transcriber: transcriber, locale: locale)
        } catch {
            throw error
        }

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

        guard let inputSequence else { return transcriber }

        try await analyzer?.start(inputSequence: inputSequence)

        return transcriber
    }

    /// Stream audio buffer to the transcriber
    func streamAudioToTranscriber(_ buffer: AVAudioPCMBuffer, converter: BufferConverter) async throws {
        guard let inputBuilder, let analyzerFormat else {
            throw AuralKitError.invalidAudioDataType
        }

        let converted = try converter.convertBuffer(buffer, to: analyzerFormat)
        let input = AnalyzerInput(buffer: converted)

        inputBuilder.yield(input)
    }

    /// Process audio buffer synchronously (for use in callbacks)
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: BufferConverter) throws {
        guard let inputBuilder, let analyzerFormat else {
            throw AuralKitError.invalidAudioDataType
        }

        let converted = try converter.convertBuffer(buffer, to: analyzerFormat)
        let input = AnalyzerInput(buffer: converted)
        inputBuilder.yield(input)
    }

    /// Stop transcribing and clean up
    func stop() async {
        inputBuilder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()

        inputBuilder = nil
        inputSequence = nil
        analyzerFormat = nil
        analyzer = nil
        transcriber = nil
    }
}
