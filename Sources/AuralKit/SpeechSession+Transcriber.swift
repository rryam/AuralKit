import Foundation
@preconcurrency import AVFoundation
import Speech

extension SpeechDetector: @retroactive SpeechModule, @unchecked @retroactive Sendable {}

@MainActor
extension SpeechSession {

    // MARK: - Transcriber Setup and Cleanup

    func setUpSpeechTranscriber(
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) async throws -> SpeechTranscriber {
        if Self.shouldLog(.notice) {
            Self.logger.notice("Setting up transcriber")
        }

        let transcriber = try createSpeechTranscriber()
        let modules = configureModules(transcriber: transcriber)
        try await ensureModels(modules: modules)
        try await configureAnalyzerContext(contextualStrings: contextualStrings)
        try await startAnalyzer(modules: modules)

        return transcriber
    }

    @available(iOS 26.0, macOS 26.0, *)
    func setUpDictationTranscriber(
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) async throws -> DictationTranscriber {
        if Self.shouldLog(.notice) {
            Self.logger.notice("Setting up dictation transcriber")
        }

        let transcriber = try createDictationTranscriber()
        let modules = configureModules(transcriber: transcriber)
        try await ensureModels(modules: modules)
        try await configureAnalyzerContext(contextualStrings: contextualStrings)
        try await startAnalyzer(modules: modules)

        return transcriber
    }

    private func createSpeechTranscriber() throws -> SpeechTranscriber {
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

        return transcriber
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func createDictationTranscriber() throws -> DictationTranscriber {
        let basePreset = DictationTranscriber.Preset.progressiveLongDictation
        var contentHints = basePreset.contentHints

        if let configuration = customVocabularyConfiguration {
            contentHints.insert(.customizedLanguage(modelConfiguration: configuration))
        }

        dictationTranscriber = DictationTranscriber(
            locale: locale,
            contentHints: contentHints,
            transcriptionOptions: basePreset.transcriptionOptions,
            reportingOptions: basePreset.reportingOptions,
            attributeOptions: basePreset.attributeOptions
        )

        guard let dictationTranscriber else {
            throw SpeechSessionError.recognitionStreamSetupFailed
        }

        return dictationTranscriber
    }

    @discardableResult
    private func configureModules(transcriber: any SpeechModule) -> [any SpeechModule] {
        var modules: [any SpeechModule] = []

        if let configuration = voiceActivationConfiguration {
            let detector = SpeechDetector(
                detectionOptions: configuration.detectionOptions,
                reportResults: configuration.reportResults
            )
            speechDetector = detector
            _ = prepareSpeechDetectorResultsStream(reportResults: configuration.reportResults)
            modules.append(detector)
            if Self.shouldLog(.info) {
                let sensitivity = String(describing: configuration.detectionOptions.sensitivityLevel)
                Self.logger.info(
                    "Added speech detector module with sensitivity: \(sensitivity, privacy: .public)"
                )
            }
        } else {
            speechDetector = nil
            tearDownSpeechDetectorStream()
            voiceActivationConfiguration = nil
        }

        modules.append(transcriber)

        analyzer = SpeechAnalyzer(modules: modules)
        if Self.shouldLog(.debug) {
            Self.logger.debug("Analyzer instantiated with \(modules.count, privacy: .public) module(s)")
        }

        return modules
    }

    private func ensureModels(modules: [any SpeechModule]) async throws {
        if let transcriber {
            try await modelManager.ensureModel(module: transcriber, locale: locale)
            if Self.shouldLog(.info) {
                let localeIdentifier = locale.identifier(.bcp47)
                Self.logger.info("Model ensured for locale \(localeIdentifier, privacy: .public)")
            }
        } else if let dictationTranscriber {
            try await modelManager.ensureModel(module: dictationTranscriber, locale: locale)
            if Self.shouldLog(.info) {
                let localeIdentifier = locale.identifier(.bcp47)
                Self.logger.info("Dictation model ensured for locale \(localeIdentifier, privacy: .public)")
            }
        }

        let supplementalModules = modules.filter { !($0 is SpeechTranscriber) && !($0 is DictationTranscriber) }
        if !supplementalModules.isEmpty {
            if Self.shouldLog(.info) {
                Self.logger.info(
                    "Ensuring supplemental assets for \(supplementalModules.count, privacy: .public) module(s)"
                )
            }
            try await modelManager.ensureAssets(for: supplementalModules)
        }
    }

    private func configureAnalyzerContext(
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]?
    ) async throws {
        guard let contextualStrings, !contextualStrings.isEmpty, let analyzer else { return }

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

    private func startAnalyzer(modules: [any SpeechModule]) async throws {
        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)
        (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()

        guard let inputSequence else { return }

        try await analyzer?.start(inputSequence: inputSequence)
        if Self.shouldLog(.info) {
            Self.logger.info("Analyzer started")
        }

        if voiceActivationConfiguration != nil {
            startSpeechDetectorMonitoring()
        }
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
        dictationTranscriber = nil
        if Self.shouldLog(.debug) {
            Self.logger.debug("Transcriber cleanup complete")
        }
    }
}
