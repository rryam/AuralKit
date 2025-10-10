import Foundation
import AVFoundation
import Speech

@MainActor
extension SpeechSession {

    // MARK: - Transcriber Setup and Cleanup

    func setUpTranscriber(
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) async throws -> SpeechTranscriber {
        Self.log("Setting up transcriber", level: .notice)
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

#if compiler(>=6.2.1) // SpeechDetector conforms to SpeechModule in iOS 26.1+
        if let configuration = voiceActivationConfiguration {
            let detector = SpeechDetector(
                detectionOptions: configuration.detectionOptions,
                reportResults: configuration.reportResults
            )
            speechDetector = detector
            _ = prepareSpeechDetectorResultsStream(reportResults: configuration.reportResults)
            let detectorModule: any SpeechModule = detector
            modules.append(detectorModule)
            Self.log("Added speech detector module with sensitivity: \(configuration.detectionOptions.sensitivityLevel)", level: .info)
        } else {
            speechDetector = nil
            tearDownSpeechDetectorStream()
            voiceActivationConfiguration = nil
        }
#else
        // SpeechDetector doesn't conform to SpeechModule on iOS/macOS 26.0
        // Voice activation requires iOS/macOS 26.1+ SDK
        speechDetector = nil
        tearDownSpeechDetectorStream()
        voiceActivationConfiguration = nil
#endif

        modules.append(transcriber)

        analyzer = SpeechAnalyzer(modules: modules)
        Self.log("Analyzer instantiated with \(modules.count) module(s)", level: .debug)

        try await modelManager.ensureModel(transcriber: transcriber, locale: locale)
        Self.log("Model ensured for locale \(locale.identifier(.bcp47))", level: .info)

        if modules.count > 1 {
            let supplementalModules = modules.filter { !($0 is SpeechTranscriber) }
            if !supplementalModules.isEmpty {
                Self.log("Ensuring supplemental assets for \(supplementalModules.count) module(s)", level: .info)
                try await modelManager.ensureAssets(for: supplementalModules)
            }
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
            Self.log("Configured contextual strings for analyzer", level: .debug)
        }

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)
        (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

        guard let inputSequence else { return transcriber }

        try await analyzer?.start(inputSequence: inputSequence)
        Self.log("Analyzer started", level: .info)

        if voiceActivationConfiguration != nil {
            startSpeechDetectorMonitoring()
        }

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
        Self.log("Stopping transcriber and cleaning up", level: .debug)

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
        Self.log("Transcriber cleanup complete", level: .debug)
    }
}
