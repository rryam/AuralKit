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
public final class SpeechSession: @unchecked Sendable {
    
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

    private let permissionsManager = PermissionsManager()
    private let converter = BufferConverter()
    private let modelManager = ModelManager()

    private lazy var audioEngine = AVAudioEngine()
    private var isAudioStreaming = false

    private let locale: Locale
    private let reportingOptions: Set<SpeechTranscriber.ReportingOption>
    private let attributeOptions: Set<SpeechTranscriber.ResultAttributeOption>
    
#if os(iOS)
    private let audioConfig: AudioSessionConfiguration
#endif

#if os(iOS) || os(macOS)
    private var audioInputConfigurationContinuation: AsyncStream<AudioInputInfo?>.Continuation?
    public private(set) lazy var audioInputConfigurationStream: AsyncStream<AudioInputInfo?> = {
        AsyncStream { [weak self] continuation in
            self?.audioInputConfigurationContinuation = continuation
        }
    }()
#endif
    
    // Transcriber components
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    
    // Stream state management
    private var continuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation?
    private var recognizerTask: Task<Void, Never>?
    private var streamingActive = false

    // Notification Handling
    private var routeChangeObserver: NSObjectProtocol?

    // MARK: - Init

    /// Create a new transcriber instance.
    ///
    /// - Parameters:
    ///   - locale: Desired transcription locale. Defaults to the device locale and is
    ///     validated against `SpeechTranscriber.supportedLocales`. If the locale is not yet installed,
    ///     `AuralKit` automatically downloads the corresponding on-device model.
    ///   - reportingOptions: Options controlling when and how results are delivered.
    ///     Defaults to `.volatileResults` (partial results) and `.alternativeTranscriptions`.
    ///   - attributeOptions: Options controlling what metadata is included with results.
    ///     Defaults to `.audioTimeRange` (timing info) and `.transcriptionConfidence`.
    public init(
        locale: Locale = .current,
        reportingOptions: Set<SpeechTranscriber.ReportingOption> = defaultReportingOptions,
        attributeOptions: Set<SpeechTranscriber.ResultAttributeOption> = defaultAttributeOptions
    ) {
        self.locale = locale
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
    ///   - reportingOptions: Options controlling when and how results are delivered.
    ///     Defaults to `.volatileResults` (partial results) and `.alternativeTranscriptions`.
    ///   - attributeOptions: Options controlling what metadata is included with results.
    ///     Defaults to `.audioTimeRange` (timing info) and `.transcriptionConfidence`.
    ///   - audioConfig: Audio session configuration for iOS. Controls category, mode, and options.
    public init(
        locale: Locale = .current,
        reportingOptions: Set<SpeechTranscriber.ReportingOption> = defaultReportingOptions,
        attributeOptions: Set<SpeechTranscriber.ResultAttributeOption> = defaultAttributeOptions,
        audioConfig: AudioSessionConfiguration = .default
    ) {
        self.locale = locale
        self.reportingOptions = reportingOptions
        self.attributeOptions = attributeOptions
        self.audioConfig = audioConfig
#if os(iOS) || os(macOS)
        setupAudioConfigurationObservers()
#endif
    }
#endif

    deinit {
#if os(iOS) || os(macOS)
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        audioInputConfigurationContinuation?.finish()
#endif
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
        let (stream, continuation) = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()

        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.cleanup(cancelRecognizer: true)
            }
        }

        Task {
            if self.continuation != nil || recognizerTask != nil || streamingActive {
                continuation.finish(throwing: SpeechSessionError.recognitionStreamSetupFailed)
                return
            }

            self.continuation = continuation
            await startPipeline(with: continuation, contextualStrings: contextualStrings)
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
        await cleanup(cancelRecognizer: true)
        await finishStream(error: nil)
    }

    // MARK: - Private helpers

    private func startPipeline(
        with continuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation,
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) async {
        do {
            try await permissionsManager.ensurePermissions()

#if os(iOS)
            try await MainActor.run {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(audioConfig.category, mode: audioConfig.mode, options: audioConfig.options)
                try audioSession.setActive(true)
            }
#endif
#if os(iOS) || os(macOS)
            publishCurrentAudioInputInfo()
#endif

            let transcriber = try await setUpTranscriber(contextualStrings: contextualStrings)

            recognizerTask = Task<Void, Never> { [weak self] in
                guard let self else { return }

                do {
                    for try await result in transcriber.results {
                        continuation.yield(result)
                    }
                    await self.finishFromRecognizerTask(error: nil)
                } catch is CancellationError {
                    // Cancellation handled by cleanup logic
                } catch {
                    await self.finishFromRecognizerTask(error: error)
                }
            }

            try startAudioStreaming()

            streamingActive = true
        } catch {
            await finishWithStartupError(error)
        }
    }

    private func finishWithStartupError(_ error: Error) async {
        await cleanup(cancelRecognizer: true)
        await finishStream(error: error)
    }

    private func finishFromRecognizerTask(error: Error?) async {
        await cleanup(cancelRecognizer: false)
        await finishStream(error: error)
    }

    private func cleanup(cancelRecognizer: Bool) async {
        let task = recognizerTask
        recognizerTask = nil
        
        if cancelRecognizer {
            task?.cancel()
        }

        streamingActive = false
        stopAudioStreaming()
        await stopTranscriberAndCleanup()
    }

    private func finishStream(error: Error?) async {
        guard let cont = continuation else { return }
        continuation = nil

        if let error {
            cont.finish(throwing: error)
        } else {
            cont.finish()
        }
    }
    
    // MARK: - Audio Streaming

    private func startAudioStreaming() throws {
        guard !isAudioStreaming else {
            throw SpeechSessionError.recognitionStreamSetupFailed
        }

        audioEngine.inputNode.removeTap(onBus: 0)

        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)

        audioEngine.inputNode.installTap(onBus: 0,
                                         bufferSize: 4096,
                                         format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            do {
                try self.processAudioBuffer(buffer)
            } catch {
                // Audio processing error - ignore and continue
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isAudioStreaming = true
    }
    
    private func stopAudioStreaming() {
        guard isAudioStreaming else { return }
        audioEngine.stop()
        isAudioStreaming = false
    }
    
#if os(iOS) || os(macOS)
    /// Sets up platform-specific notifications for audio route/configuration changes.
    private func setupAudioConfigurationObservers() {
#if os(iOS)
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
            }

            Task {
                await self.handleRouteChange(reason, notification: notification)
            }
        }
#elseif os(macOS)
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.handleEngineConfigurationChange()
            }
        }
#endif
    }
#endif

#if os(iOS)
    private func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason, notification: Notification) async {
        let session = AVAudioSession.sharedInstance()
        let previousRoute = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
        let previousPortType = previousRoute?.inputs.first?.portType
        let currentPortType = session.currentRoute.inputs.first?.portType

        guard previousPortType != currentPortType else {
            return
        }

        do {
            try await reset()
        } catch {
            print("Failed to reset audio engine after route change: \(error.localizedDescription)")
        }

        publishCurrentAudioInputInfo()
    }
#elseif os(macOS)
    private func handleEngineConfigurationChange() async {
        do {
            try await reset()
        } catch {
            print("Failed to reset audio engine after configuration change: \(error.localizedDescription)")
        }

        publishCurrentAudioInputInfo()
    }
#endif
    
#if os(iOS) || os(macOS)
    private func publishCurrentAudioInputInfo() {
#if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        if let input = audioSession.currentRoute.inputs.first {
            audioInputConfigurationContinuation?.yield(AudioInputInfo(from: input))
        } else {
            audioInputConfigurationContinuation?.yield(nil)
        }
#elseif os(macOS)
        do {
            let info = try AudioInputInfo.current()
            audioInputConfigurationContinuation?.yield(info)
        } catch {
            print("Failed to obtain audio input details: \(error.localizedDescription)")
            audioInputConfigurationContinuation?.yield(nil)
        }
#endif
    }
#endif
    
    private func reset() async throws {
        let wasStreaming = isAudioStreaming

        if wasStreaming {
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        audioEngine.stop()
        audioEngine.reset()
        isAudioStreaming = false

        guard wasStreaming else { return }
        try startAudioStreaming()
    }
    
    // MARK: - Transcriber Setup and Management
    
    /// Set up the transcriber with the configured locale and options
    private func setUpTranscriber(
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

        // Set up analysis context with contextual strings if provided
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

    /// Process audio buffer synchronously (for use in callbacks)
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) throws {
        guard let inputBuilder, let analyzerFormat else {
            throw SpeechSessionError.invalidAudioDataType
        }

        let converted = try converter.convertBuffer(buffer, to: analyzerFormat)
        let input = AnalyzerInput(buffer: converted)
        inputBuilder.yield(input)
    }

    /// Stop transcribing and clean up
    private func stopTranscriberAndCleanup() async {
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
