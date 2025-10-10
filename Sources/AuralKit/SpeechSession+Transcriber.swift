import Foundation
import AVFoundation
import Speech

@MainActor
extension SpeechSession {

    // MARK: - Transcriber Setup and Cleanup

    func setUpTranscriber(
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) async throws -> SpeechTranscriber {
        let effectiveTranscriptionOptions = preset?.transcriptionOptions ?? []
        let effectiveReportingOptions = preset?.reportingOptions ?? reportingOptions
        let effectiveAttributeOptions = preset?.attributeOptions ?? attributeOptions

        transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: effectiveTranscriptionOptions,
            reportingOptions: effectiveReportingOptions,
            attributeOptions: effectiveAttributeOptions
        )

        guard let transcriber else {
            throw SpeechSessionError.recognitionStreamSetupFailed
        }

        var modules: [any SpeechModule] = []

        if let configuration = voiceActivationConfiguration {
            let detector = SpeechDetector(
                detectionOptions: configuration.detectionOptions,
                reportResults: configuration.reportResults
            )
            speechDetector = detector
            _ = prepareSpeechDetectorResultsStream(reportResults: configuration.reportResults)
            modules.append(detector)
        } else {
            speechDetector = nil
            tearDownSpeechDetectorStream()
        }

        modules.append(transcriber)

        analyzer = SpeechAnalyzer(modules: modules)

        try await modelManager.ensureModel(transcriber: transcriber, locale: locale)

        if modules.count > 1 {
            try await modelManager.ensureAssets(for: modules)
        }

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

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)
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

        tearDownSpeechDetectorStream()
        speechDetector = nil

        inputBuilder = nil
        inputSequence = nil
        analyzerFormat = nil
        analyzer = nil
        transcriber = nil
    }
}
