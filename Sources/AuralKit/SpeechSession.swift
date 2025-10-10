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
///
/// Concurrency notes:
/// - `SpeechSession` is isolated to the main actor so engine/configuration mutations happen on a
///   single thread.
/// - Audio buffers arrive on Core Audio's render thread, so the tap copies each buffer and hops back
///   to the main actor before touching analyzer state.
@MainActor
public final class SpeechSession {

    // MARK: - Status

    /// Discrete lifecycle stages for a speech transcription session.
    public enum Status: Equatable, Sendable {
        case idle
        case preparing
        case transcribing
        case paused
        case stopping
    }
    
    // MARK: - Default Configuration
    
    /// Default reporting options: provides partial results and alternative transcriptions
    public static let defaultReportingOptions: Set<SpeechTranscriber.ReportingOption> = [
        .volatileResults,
        .alternativeTranscriptions
    ]
    
    /// Default attribute options: includes timing and confidence metadata
    public static let defaultAttributeOptions: Set<SpeechTranscriber.ResultAttributeOption> = [
        .audioTimeRange,
        .transcriptionConfidence
    ]

#if os(iOS)
    /// Audio session configuration for iOS
    public struct AudioSessionConfiguration: Sendable {
        public let category: AVAudioSession.Category
        public let mode: AVAudioSession.Mode
        public let options: AVAudioSession.CategoryOptions
        
        public init(
            category: AVAudioSession.Category = .playAndRecord,
            mode: AVAudioSession.Mode = .spokenAudio,
            options: AVAudioSession.CategoryOptions = .duckOthers
        ) {
            self.category = category
            self.mode = mode
            self.options = options
        }
        
        public static let `default` = AudioSessionConfiguration()
    }
#endif

    // MARK: - Properties

    let permissionsManager = PermissionsManager()
    let converter = BufferConverter()
    let modelManager = ModelManager()

    lazy var audioEngine = AVAudioEngine()
    var isAudioStreaming = false

    let locale: Locale
    let preset: SpeechTranscriber.Preset?
    let reportingOptions: Set<SpeechTranscriber.ReportingOption>
    let attributeOptions: Set<SpeechTranscriber.ResultAttributeOption>

    /// Current lifecycle status for the session.
    public private(set) var status: Status = .idle
    private var statusContinuation: AsyncStream<Status>.Continuation?
    public private(set) lazy var statusStream: AsyncStream<Status> = {
        AsyncStream<Status> { [weak self] continuation in
            guard let self else { return }
            continuation.yield(self.status)
            self.statusContinuation = continuation
        }
    }()
    
#if os(iOS)
    let audioConfig: AudioSessionConfiguration
#endif

#if os(iOS) || os(macOS)
    var audioInputConfigurationContinuation: AsyncStream<AudioInputInfo?>.Continuation?
    public private(set) lazy var audioInputConfigurationStream: AsyncStream<AudioInputInfo?> = {
        AsyncStream { [weak self] continuation in
            self?.audioInputConfigurationContinuation = continuation
        }
    }()
#endif
    
    // Transcriber components
    var transcriber: SpeechTranscriber?
    var analyzer: SpeechAnalyzer?
    var inputSequence: AsyncStream<AnalyzerInput>?
    var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    var analyzerFormat: AVAudioFormat?
    private var voiceActivationConfiguration: VoiceActivationConfiguration?
    
    // Stream state management
    var continuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation?
    var recognizerTask: Task<Void, Never>?
    var streamingActive = false

    // Notification Handling
    var routeChangeObserver: NSObjectProtocol?

    // Voice activation state
    private var speechDetectorResultsContinuation: AsyncStream<SpeechDetector.Result>.Continuation?
    public private(set) var speechDetectorResultsStream: AsyncStream<SpeechDetector.Result>?
    private var speechDetectorResultsTask: Task<Void, Never>?

    private struct VoiceActivationConfiguration {
        let detectionOptions: SpeechDetector.DetectionOptions
        let reportResults: Bool
    }

    private func tearDownSpeechDetectorStream() {
        speechDetectorResultsTask?.cancel()
        speechDetectorResultsTask = nil
        speechDetectorResultsContinuation?.finish()
        speechDetectorResultsContinuation = nil
        speechDetectorResultsStream = nil
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
        audioInputConfigurationContinuation?.finish()
#endif
        statusContinuation?.finish()
    }

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

    // MARK: - Public API

    public var isVoiceActivationEnabled: Bool {
        voiceActivationConfiguration != nil
    }

    public func configureVoiceActivation(
        detectionOptions: SpeechDetector.DetectionOptions = .init(sensitivityLevel: .medium),
        reportResults: Bool = false
    ) {
        voiceActivationConfiguration = VoiceActivationConfiguration(
            detectionOptions: detectionOptions,
            reportResults: reportResults
        )

        if !reportResults {
            tearDownSpeechDetectorStream()
        }
    }

    public func disableVoiceActivation() {
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

        guard continuation == nil, recognizerTask == nil, streamingActive == false else {
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

// MARK: - Status Helpers

@MainActor
extension SpeechSession {
    func setStatus(_ newStatus: Status) {
        guard status != newStatus else { return }
        status = newStatus
        statusContinuation?.yield(newStatus)
    }

    func prepareForStop() {
        switch status {
        case .idle, .stopping:
            break
        default:
            setStatus(.stopping)
        }
    }
}
