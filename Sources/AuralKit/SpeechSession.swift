import Foundation
import AVFoundation
import Speech

// MARK: - SpeechSession

/// A session for streaming live speech-to-text using the SpeechTranscriber/SpeechAnalyzer stack.
///
/// `SpeechSession` hides the details of microphone capture, buffer conversion, model installation,
/// and result streaming. The API is designed around Swift Concurrency and integrates cleanly with
/// `for try await` loops.
///
/// ```swift
/// let session = SpeechSession(locale: .current)
///
/// Task {
///     do {
///         for try await result in session.startTranscribing() {
///             if result.isFinal {
///                 print("Final: \(result.text)")
///             } else {
///                 print("Partial: \(result.text)")
///             }
///         }
///     } catch {
///         // Handle `SpeechSessionError`
///     }
/// }
/// ```
///
/// Call `stopTranscribing()` to end capture and unwind the stream. The same instance may be reused
/// for subsequent transcription sessions.
@MainActor
public final class SpeechSession {

    /// Discrete lifecycle stages for a speech transcription session.
    public enum Status: Equatable, Sendable {
        case idle
        case preparing
        case transcribing
        case paused
        case stopping
    }

    // MARK: - Properties

    let converter = BufferConverter()
    let modelManager = ModelManager()

    lazy var audioEngine = AVAudioEngine()
    var isAudioStreaming = false

    let locale: Locale
    let preset: SpeechTranscriber.Preset?
    let reportingOptions: Set<SpeechTranscriber.ReportingOption>
    let attributeOptions: Set<SpeechTranscriber.ResultAttributeOption>

    var statusContinuations: [UUID: AsyncStream<Status>.Continuation] = [:]

#if os(iOS)
    let audioConfig: AudioSessionConfiguration
    var isAudioSessionActive = false
    var interruptionObserver: NSObjectProtocol?
    var shouldResumeAfterInterruption = false
#endif

#if os(iOS) || os(macOS)
    var audioInputContinuations: [UUID: AsyncStream<AudioInputInfo?>.Continuation] = [:]
#endif

    // Transcriber components
    var transcriber: SpeechTranscriber?
    var speechDetector: SpeechDetector?
    var analyzer: SpeechAnalyzer?
    var inputSequence: AsyncStream<AnalyzerInput>?
    var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    var analyzerFormat: AVAudioFormat?
    var voiceActivationConfiguration: VoiceActivationConfiguration?

    // MARK: - Public Observables

    /// Current lifecycle status for the session.
    public internal(set) var status: Status = .idle

    /// Async stream that emits lifecycle status updates, beginning with the current status.
    public var statusStream: AsyncStream<Status> {
        AsyncStream { [weak self] continuation in
            let id = UUID()
            Task { @MainActor [weak self] in
                guard let self else { return }
                continuation.yield(self.status)
                self.statusContinuations[id] = continuation
            }

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.statusContinuations.removeValue(forKey: id)
                }
            }
        }
    }

#if os(iOS) || os(macOS)
    /// Stream that delivers `AudioInputInfo` updates whenever the active audio input changes.
    public var audioInputConfigurationStream: AsyncStream<AudioInputInfo?> {
        AsyncStream { [weak self] continuation in
            let id = UUID()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.audioInputContinuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.audioInputContinuations.removeValue(forKey: id)
                }
            }
        }
    }
#endif

    /// Stream of speech detector results when voice activation reporting is enabled; `nil` otherwise.
    public internal(set) var speechDetectorResultsStream: AsyncStream<SpeechDetector.Result>?

    /// Reflects the speech detector's most recent state; defaults to `true` when monitoring is inactive.
    public internal(set) var isSpeechDetected: Bool = true

    /// Progress of the ongoing model download, if any.
    ///
    /// Poll or observe this property to drive UI such as `ProgressView`. The value is non-nil only
    /// while a locale model is downloading.
    ///
    /// ```swift
    /// let session = SpeechSession()
    /// if let progress = session.modelDownloadProgress {
    ///     print("Downloading: \(progress.fractionCompleted * 100)%")
    /// }
    /// ```
    public var modelDownloadProgress: Progress? {
        modelManager.currentDownloadProgress
    }

    /// Returns `true` when voice activation has been configured for the session.
    public var isVoiceActivationEnabled: Bool {
        voiceActivationConfiguration != nil
    }

    // Stream state management
    var continuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation?
    var recognizerTask: Task<Void, Never>?
    var fileIngestionTask: Task<Void, Never>?
    /// Discrete source types currently feeding the analyzer pipeline.
    enum StreamingMode: Equatable, Sendable {
        case inactive
        case liveMicrophone
        case filePlayback
    }

    var streamingMode: StreamingMode = .inactive

    // Notification Handling
    var routeChangeObserver: NSObjectProtocol?

    // Voice activation state
    var speechDetectorResultsContinuation: AsyncStream<SpeechDetector.Result>.Continuation?
    var speechDetectorResultsTask: Task<Void, Never>?

    struct VoiceActivationConfiguration {
        let detectionOptions: SpeechDetector.DetectionOptions
        let reportResults: Bool
    }

    // MARK: - Init

    /// Create a new transcriber instance.
    ///
    /// - Parameters:
    ///   - locale: Desired transcription locale. Defaults to the device locale and is
    ///     validated against `SpeechTranscriber.supportedLocales`. If the locale is not yet installed,
    ///     `AuralKit` automatically downloads the corresponding on-device model.
    ///   - preset: Optional preset that configures transcription, reporting, and attribute options.
    ///   - reportingOptions: Options controlling when and how results are delivered when no preset is provided.
    ///     Defaults to `.volatileResults` (partial results) and `.alternativeTranscriptions`.
    ///   - attributeOptions: Options controlling what metadata is included with results when no preset is provided.
    ///     Defaults to `.audioTimeRange` (timing info) and `.transcriptionConfidence`.
    public init(
        locale: Locale = .current,
        preset: SpeechTranscriber.Preset? = nil,
        reportingOptions: Set<SpeechTranscriber.ReportingOption> = defaultReportingOptions,
        attributeOptions: Set<SpeechTranscriber.ResultAttributeOption> = defaultAttributeOptions
    ) {
        self.locale = locale
        self.preset = preset
        self.reportingOptions = reportingOptions
        self.attributeOptions = attributeOptions
#if os(iOS)
        self.audioConfig = AudioSessionConfiguration.default
#endif
#if os(iOS) || os(macOS)
        setupAudioConfigurationObservers()
#endif
    }

#if os(iOS)
    /// Create a new transcriber instance with custom audio session configuration (iOS only).
    ///
    /// - Parameters:
    ///   - locale: Desired transcription locale. Defaults to the device locale and is
    ///     validated against `SpeechTranscriber.supportedLocales`. If the locale is not yet installed,
    ///     `AuralKit` automatically downloads the corresponding on-device model.
    ///   - preset: Optional preset that configures transcription, reporting, and attribute options.
    ///   - reportingOptions: Options controlling when and how results are delivered when no preset is provided.
    ///     Defaults to `.volatileResults` (partial results) and `.alternativeTranscriptions`.
    ///   - attributeOptions: Options controlling what metadata is included with results when no preset is provided.
    ///     Defaults to `.audioTimeRange` (timing info) and `.transcriptionConfidence`.
    ///   - audioConfig: Audio session configuration for iOS. Controls category, mode, and options.
    public init(
        locale: Locale = .current,
        preset: SpeechTranscriber.Preset? = nil,
        reportingOptions: Set<SpeechTranscriber.ReportingOption> = defaultReportingOptions,
        attributeOptions: Set<SpeechTranscriber.ResultAttributeOption> = defaultAttributeOptions,
        audioConfig: AudioSessionConfiguration = .default
    ) {
        self.locale = locale
        self.preset = preset
        self.reportingOptions = reportingOptions
        self.attributeOptions = attributeOptions
        self.audioConfig = audioConfig
#if os(iOS) || os(macOS)
        setupAudioConfigurationObservers()
#endif
    }
#endif

    @MainActor
    deinit {
#if os(iOS) || os(macOS)
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        finishAudioInputStreams()
#endif
#if os(iOS)
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
#endif
        finishStatusStreams()
    }

    // MARK: - Public API

    /// Configure optional voice activation to reduce power consumption during transcription.
    ///
    /// Voice activation uses a Voice Activity Detection (VAD) model to identify speech and skip
    /// processing silent audio segments, saving power. However, there is a tradeoff: if the model
    /// drops audio that actually contains speech, transcription accuracy may suffer.
    ///
    /// - Important: Updates take effect the next time a transcription pipeline is started.
    ///   Stop and restart an active session for changes to apply.
    ///
    /// - Note: For use cases with a lot of silence, it may be tempting to always enable voice
    ///   activation. Evaluate the power savings against potential accuracy loss for your specific
    ///   context. The `sensitivityLevel` controls how aggressive the VAD model will be:
    ///   - `.low`: More forgiving, less likely to drop speech but uses more power
    ///   - `.medium`: Recommended for most use cases (default)
    ///   - `.high`: More aggressive, saves more power but may drop speech
    ///
    /// - Parameters:
    ///   - detectionOptions: Configuration for the VAD model. Defaults to
    ///     `.init(sensitivityLevel: .medium)`, which is recommended for most use cases.
    ///   - reportResults: When `true`, enables the `speechDetectorResultsStream` to report
    ///     moment-to-moment VAD results. When `false` (default), VAD operates as a silent
    ///     power optimization without reporting individual detection events.
    public func configureVoiceActivation(
        detectionOptions: SpeechDetector.DetectionOptions = .init(sensitivityLevel: .medium),
        reportResults: Bool = false
    ) {
        if Self.shouldLog(.info) {
            let sensitivityDescription = String(describing: detectionOptions.sensitivityLevel)
            Self.logger.info(
                """
                Configuring voice activation (sensitivity: \(sensitivityDescription, privacy: .public), \
                reportResults: \(reportResults, privacy: .public))
                """
            )
        }
        voiceActivationConfiguration = VoiceActivationConfiguration(
            detectionOptions: detectionOptions,
            reportResults: reportResults
        )

        isSpeechDetected = true
        if reportResults {
            _ = prepareSpeechDetectorResultsStream(reportResults: true)
        } else {
            tearDownSpeechDetectorStream()
        }
    }

    /// Disable voice activation and tear down any active detector streams.
    ///
    /// After calling this method, the session will process all audio without power-saving
    /// voice activity detection. Changes take effect on the next transcription start.
    public func disableVoiceActivation() {
        if Self.shouldLog(.info) {
            Self.logger.info("Disabling voice activation")
        }
        voiceActivationConfiguration = nil
        tearDownSpeechDetectorStream()
    }

    /// Start streaming live microphone audio to the speech analyzer.
    ///
    /// The returned `AsyncThrowingStream` yields `SpeechTranscriber.Result` chunks containing both text and
    /// timing metadata (`.audioTimeRange`), as well as whether the result is final or volatile (partial).
    /// Consume the stream with `for try await` and call `stopTranscribing()` to finish early.
    ///
    /// - Parameter contextualStrings: Optional dictionary mapping contextual strings tags
    ///   to arrays of contextual words that help improve transcription accuracy. For example,
    ///   use `.general` for domain-specific terminology or `.personal` for names.
    /// - Returns: An async throwing stream of transcription results.
    /// - Throws: `SpeechSessionError` if permissions are denied, locale is unsupported,
    ///   transcription setup fails, or context setup fails.
    ///
    /// # Example
    /// ```swift
    /// // Basic usage
    /// for try await result in session.startTranscribing() {
    ///     if result.isFinal {
    ///         // Final result - accumulate this
    ///     } else {
    ///         // Volatile result - replace previous partial
    ///     }
    /// }
    ///
    /// // With contextual strings
    /// for try await result in session.startTranscribing(
    ///     contextualStrings: [.general: ["SwiftUI", "Combine", "AsyncStream"]]
    /// ) {
    ///     // Process results...
    /// }
    /// ```
    public func startTranscribing(
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) -> AsyncThrowingStream<SpeechTranscriber.Result, Error> {
        let (stream, newContinuation) = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()

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
        continuation = newContinuation
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.startPipeline(with: newContinuation, contextualStrings: contextualStrings)
        }
        return stream
    }
    /// Start streaming live microphone audio to the speech analyzer with contextual strings.
    ///
    /// Convenience method that takes a simple array of contextual words and maps them to
    /// the `.general` analysis context property internally.
    ///
    /// - Parameter contextualStrings: Optional array of contextual words that help improve
    ///   transcription accuracy for domain-specific terminology.
    /// - Returns: An async throwing stream of transcription results.
    /// - Throws: `SpeechSessionError` if permissions are denied, locale is unsupported,
    ///   transcription setup fails, or context setup fails.
    ///
    /// # Example
    /// ```swift
    /// for try await result in session.startTranscribing(
    ///     contextualStrings: ["SwiftUI", "Combine", "AsyncStream"]
    /// ) {
    ///     // Process results...
    /// }
    /// ```
    public func startTranscribing(
        contextualStrings: [String]
    ) -> AsyncThrowingStream<SpeechTranscriber.Result, Error> {
        return startTranscribing(contextualStrings: [.general: contextualStrings])
    }
    /// Stop capturing audio and finish the current transcription stream.
    ///
    /// Safe to call even if `startTranscribing()` has not been invoked or the stream has already
    /// completed; the method simply waits for cleanup and returns.
    public func stopTranscribing() async {
        prepareForStop()
        await cleanup(cancelRecognizer: true)
        await finishStream(error: nil)
    }

    /// Pause capture without tearing down the analyzer pipeline.
    ///
    /// Safe to call only when the session is actively transcribing. Additional calls are ignored.
    public func pauseTranscribing() async {
        guard status == .transcribing else { return }
        stopAudioStreaming()
        setStatus(.paused)
    }

    /// Resume a paused capture session.
    ///
    /// - Throws: `SpeechSessionError` if audio streaming cannot restart.
    public func resumeTranscribing() async throws {
        guard status == .paused else { return }
        do {
            try startAudioStreaming()
            setStatus(.transcribing)
        } catch {
            prepareForStop()
            await cleanup(cancelRecognizer: true)
            await finishStream(error: error)
            throw error
        }
    }
}
