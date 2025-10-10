import Foundation
import AVFoundation
import Speech

@MainActor
extension SpeechSession {

    // MARK: - Transcriber Setup and Cleanup

    func setUpTranscriber(
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) async throws -> SpeechTranscriber {
        if Self.shouldLog(.notice) {
            Self.logger.notice("Setting up transcriber")
        }
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
            if Self.shouldLog(.info) {
                let sensitivityDescription = String(describing: configuration.detectionOptions.sensitivityLevel)
                Self.logger.info("Added speech detector module with sensitivity: \(sensitivityDescription, privacy: .public)")
            }
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
        if Self.shouldLog(.debug) {
            Self.logger.debug("Analyzer instantiated with \(modules.count, privacy: .public) module(s)")
        }

        try await modelManager.ensureModel(transcriber: transcriber, locale: locale)
        if Self.shouldLog(.info) {
            let localeIdentifier = locale.identifier(.bcp47)
            Self.logger.info("Model ensured for locale \(localeIdentifier, privacy: .public)")
        }

        if modules.count > 1 {
            let supplementalModules = modules.filter { !($0 is SpeechTranscriber) }
            if !supplementalModules.isEmpty {
                if Self.shouldLog(.info) {
                    Self.logger.info("Ensuring supplemental assets for \(supplementalModules.count, privacy: .public) module(s)")
                }
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
            if Self.shouldLog(.debug) {
                Self.logger.debug("Configured contextual strings for analyzer")
            }
        }

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)
        (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

        guard let inputSequence else { return transcriber }

        try await analyzer?.start(inputSequence: inputSequence)
        if Self.shouldLog(.info) {
            Self.logger.info("Analyzer started")
        }

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
        if Self.shouldLog(.debug) {
            Self.logger.debug("Stopping transcriber and cleaning up")
        }

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
        if Self.shouldLog(.debug) {
            Self.logger.debug("Transcriber cleanup complete")
        }
    }
}
