import Foundation
import AVFoundation
import Speech

@MainActor
extension SpeechSession {

    // MARK: - Transcriber Setup and Cleanup

    func setUpTranscriber(
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) async throws -> SpeechTranscriber {
        transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: reportingOptions,
            attributeOptions: attributeOptions
        )

        guard let transcriber else {
            throw SpeechSessionError.recognitionStreamSetupFailed
        }

        analyzer = SpeechAnalyzer(modules: [transcriber])

        try await modelManager.ensureModel(transcriber: transcriber, locale: locale)

        if let contextualStrings, !contextualStrings.isEmpty, let analyzer {
            let analysisContext = AnalysisContext()
            for (tag, strings) in contextualStrings {
                analysisContext.contextualStrings[tag] = strings
            }
            do {
                try await analyzer.setContext(analysisContext)
            } catch {
                throw SpeechSessionError.contextSetupFailed(error)
            }
        }

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

        guard let inputSequence else { return transcriber }

        try await analyzer?.start(inputSequence: inputSequence)

        return transcriber
    }

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) throws {
        guard let inputBuilder, let analyzerFormat else {
            throw SpeechSessionError.invalidAudioDataType
        }

        let converted = try converter.convertBuffer(buffer, to: analyzerFormat)
        let input = AnalyzerInput(buffer: converted)
        inputBuilder.yield(input)
    }

    func stopTranscriberAndCleanup() async {
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
