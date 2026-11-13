import AVFoundation
import CoreMedia
import Foundation
import OSLog
import Speech

// swiftlint:disable file_length

@MainActor
extension SpeechSession {
    func resumeScreenCaptureStreamingIfNeeded(generation: Int) async throws {
        guard generation == sessionGeneration, status == .paused, streamingMode == .screenCapture else { return }
        var captureFailure: Error?
        var terminalFailure: Error?
        do {
#if canImport(ScreenCaptureKit)
            guard #available(iOS 27.0, macOS 14.0, *) else {
                throw SpeechSessionError.screenCaptureUnavailable
            }
            guard let provider = screenCaptureInputProvider as? ScreenCaptureAudioInputProvider else {
                throw SpeechSessionError.recognitionStreamSetupFailed
            }
            terminalFailure = await provider.resume { result in
                guard generation == self.sessionGeneration,
                      self.status == .paused, self.streamingMode == .screenCapture else { return }
                switch result {
                case .success:
                    self.setStatus(.transcribing)
                case .failure(let error):
                    captureFailure = error
                    self.prepareForStop()
                }
            }
            if let captureFailure { throw captureFailure }
#else
            throw SpeechSessionError.screenCaptureUnavailable
#endif
        } catch {
            let canFinish = status == .paused || (captureFailure != nil && status == .stopping)
            guard generation == sessionGeneration, canFinish, streamingMode == .screenCapture else { throw error }
            await endTranscription(error: error, generation: generation)
            throw error
        }
        if let terminalFailure { throw terminalFailure }
    }
}

#if canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit

@available(iOS 27.0, macOS 14.0, *)
public extension SpeechSession {
    /// Configuration for transcribing audio captured through ScreenCaptureKit.
    struct ScreenCaptureTranscriptionOptions {
        /// Whether captured audio should exclude audio produced by the current process.
        public var excludesCurrentProcessAudio: Bool

        /// Creates screen capture transcription options.
        public init(
            excludesCurrentProcessAudio: Bool = true
        ) {
            self.excludesCurrentProcessAudio = excludesCurrentProcessAudio
        }
    }

    /// Start transcribing audio from content selected with ScreenCaptureKit's system picker.
    ///
    /// Screen capture transcription is available on platforms where ScreenCaptureKit can stream
    /// audio as `CMSampleBuffer` values. AuralKit supplies analyzer-compatible audio to Speech
    /// and emits normal `SpeechTranscriber.Result` values.
    ///
    /// Apps using this API must include `NSScreenCaptureUsageDescription` in their Info.plist.
    ///
    /// - Parameters:
    ///   - options: ScreenCaptureKit picker and stream configuration.
    ///   - contextualStrings: Optional analysis context used to bias recognition.
    /// - Returns: An async throwing stream of transcription results.
    func startTranscribingScreenCapture(
        options: ScreenCaptureTranscriptionOptions = .init(),
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) -> AsyncThrowingStream<SpeechTranscriber.Result, Error> {
        let (stream, newContinuation) = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()

        guard continuation == nil, recognizerTask == nil, streamingMode == .inactive else {
            newContinuation.finish(throwing: SpeechSessionError.recognitionStreamSetupFailed)
            return stream
        }

        let generation = beginStreamGeneration()
        newContinuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { @MainActor [weak self] in
                await self?.handleStreamTermination(generation: generation)
            }
        }

        setStatus(.preparing)
        continuation = .speech(newContinuation)
        pipelineTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.startScreenCapturePipeline(
                with: newContinuation,
                options: options,
                contextualStrings: contextualStrings,
                generation: generation
            )
        }
        return stream
    }

    /// Start transcribing audio from selected ScreenCaptureKit content with simple contextual words.
    ///
    /// - Parameters:
    ///   - options: ScreenCaptureKit picker and stream configuration.
    ///   - contextualStrings: Contextual words applied to the `.general` analysis context.
    /// - Returns: An async throwing stream of transcription results.
    func startTranscribingScreenCapture(
        options: ScreenCaptureTranscriptionOptions = .init(),
        contextualStrings: [String]
    ) -> AsyncThrowingStream<SpeechTranscriber.Result, Error> {
        startTranscribingScreenCapture(
            options: options,
            contextualStrings: [.general: contextualStrings]
        )
    }
}

@available(iOS 27.0, macOS 14.0, *)
@MainActor
extension SpeechSession {
    func startScreenCapturePipeline(
        with streamContinuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation,
        options: ScreenCaptureTranscriptionOptions,
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]?,
        generation: Int
    ) async {
        do {
            if Self.shouldLog(.notice) {
                Self.logger.notice("Starting screen capture pipeline setup")
            }

            try Task.checkCancellation()
            try await ensureSpeechRecognitionAuthorization(context: "for screen capture transcription")
            try Task.checkCancellation()
            let transcriber = try await setUpSpeechTranscriber(contextualStrings: contextualStrings)
            try Task.checkCancellation()
            recognizerTask = createSpeechRecognizerTask(
                transcriber: transcriber,
                streamContinuation: streamContinuation,
                generation: generation
            )
            try await setUpScreenCaptureStreaming(options: options, generation: generation)
            try Task.checkCancellation()
            guard status == .preparing else { return }

            streamingMode = .screenCapture
            setStatus(.transcribing)
            activeResultKind = .speech
            if Self.shouldLog(.info) {
                Self.logger.info("Pipeline started (mode: screen capture)")
            }
        } catch is CancellationError {
            await finishFailedPipelineSetup(CancellationError(), generation: generation)
        } catch {
            if Self.shouldLog(.error) {
                Self.logger.error("Screen capture pipeline failed: \(error.localizedDescription, privacy: .public)")
            }
            await finishFailedPipelineSetup(error, generation: generation)
        }
    }

    func setUpScreenCaptureStreaming(options: ScreenCaptureTranscriptionOptions, generation: Int) async throws {
        guard let analyzerFormat, let inputBuilder else {
            throw SpeechSessionError.invalidAudioDataType
        }

        let provider = ScreenCaptureAudioInputProvider(
            options: options,
            targetFormat: analyzerFormat,
            inputContinuation: inputBuilder,
            useNativeConversion: inputProviderPreference == .automatic,
            onTermination: { [weak self] error in
                Task { @MainActor [weak self] in
                    if let error {
                        await self?.endTranscription(error: error, generation: generation)
                    } else {
                        await self?.finishTranscribing(generation: generation, sourceEnded: true)
                    }
                }
            }
        )
        screenCaptureInputProvider = provider
        try await provider.start()
    }
}

@MainActor
extension SpeechSession {
    func pauseScreenCaptureStreamingIfNeeded(generation: Int) async {
        guard generation == sessionGeneration else { return }
        guard #available(iOS 27.0, macOS 14.0, *) else { return }
        guard let provider = screenCaptureInputProvider as? ScreenCaptureAudioInputProvider else { return }
        guard await provider.pause(), generation == sessionGeneration,
              status == .transcribing, streamingMode == .screenCapture else { return }
        setStatus(.paused)
    }

    func stopScreenCaptureStreamingIfNeeded() async {
        let generation = sessionGeneration
        if let pending = screenCaptureStopTask, pending.generation == generation {
            await pending.task.value
            return
        }
        let detachedProvider = screenCaptureInputProvider
        screenCaptureInputProvider = nil
        guard #available(iOS 27.0, macOS 14.0, *) else { return }
        guard let provider = detachedProvider as? ScreenCaptureAudioInputProvider else { return }
        let task = provider.stop()
        screenCaptureStopTask = (generation, task)
        await task.value
        if screenCaptureStopTask?.generation == generation { screenCaptureStopTask = nil }
    }
}

@available(iOS 27.0, macOS 14.0, *)
@MainActor
private final class NativeScreenCaptureStream: ScreenCaptureStream {
    let stream: SCStream
    private let audio: ScreenCaptureAudioProcessor

    init(stream: SCStream, audio: ScreenCaptureAudioProcessor) {
        self.stream = stream
        self.audio = audio
    }

    func startCapture() async throws {
        defer { logCaptureState(after: "startCapture") }
        let id = ObjectIdentifier(stream)
        audio.start(id)
        do {
            try await stream.startCapture()
        } catch {
            audio.stop(id, drain: false)
            throw error
        }
    }

    func stopCapture() async throws {
        defer { logCaptureState(after: "stopCapture") }
        try await stream.stopCapture()
        audio.stop(ObjectIdentifier(stream))
    }

#if os(macOS) || targetEnvironment(macCatalyst)
    func updateContentFilter(_ filter: SCContentFilter) async throws {
        defer { logCaptureState(after: "updateContentFilter") }
        try await stream.updateContentFilter(filter)
    }
#endif

    private func logCaptureState(after operation: String) {
#if compiler(>=6.4)
        guard #available(iOS 27.0, macOS 27.0, macCatalyst 27.0, *),
              SpeechSession.shouldLog(.debug) else { return }
        SpeechSession.logger.debug(
            "SCStream.isCapturing after \(operation, privacy: .public): \(self.stream.isCapturing, privacy: .public)"
        )
#endif
    }
}

@available(iOS 27.0, macOS 14.0, *)
final class ScreenCaptureAudioInputProvider: NSObject, SCStreamOutput, SCStreamDelegate,
    SCContentSharingPickerObserver, @unchecked Sendable {

    private let options: SpeechSession.ScreenCaptureTranscriptionOptions
    private let targetFormat: AVAudioFormat
    private let onTermination: @Sendable (Error?) -> Task<Void, Never>
    private let audio: ScreenCaptureAudioProcessor

    @MainActor private let transitions: ScreenCaptureTransitions
    @MainActor private var terminalCleanupTask: Task<Void, Never>?
    private let dismissPicker: @MainActor (any SCContentSharingPickerObserver) -> Void
    private var selectionContinuation: CheckedContinuation<Void, Error>?
    private var stopped = false
    private var pickerUpdateID: UUID?
    private var filterUpdateID: UUID?

    @MainActor
    init(
        options: SpeechSession.ScreenCaptureTranscriptionOptions,
        targetFormat: AVAudioFormat,
        inputContinuation: AsyncStream<AnalyzerInput>.Continuation,
        useNativeConversion: Bool = true,
        onTermination: @escaping @Sendable (Error?) -> Task<Void, Never>,
        transitions: ScreenCaptureTransitions = ScreenCaptureTransitions(),
        dismissPicker: @escaping @MainActor (any SCContentSharingPickerObserver) -> Void = { observer in
            let picker = SCContentSharingPicker.shared
            picker.isActive = false
            picker.remove(observer)
        }
    ) {
        self.options = options
        self.targetFormat = targetFormat
        self.onTermination = onTermination
        self.audio = ScreenCaptureAudioProcessor(
            targetFormat: targetFormat, useNativeConversion: useNativeConversion, input: inputContinuation
        ) { error in
            _ = onTermination(error)
        }
        self.transitions = transitions
        self.dismissPicker = dismissPicker
        super.init()
    }

    @MainActor
    func start() async throws {
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
        let picker = SCContentSharingPicker.shared
        let configuration = SCContentSharingPickerConfiguration()
        picker.configuration = configuration
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            selectionContinuation = continuation
            picker.present()
        }
        try Task.checkCancellation()
    }

    @MainActor
    func pause() async -> Bool {
        do {
            try await transitions.pause().value
            return transitions.desiredState == .paused
        } catch {
            return false
        }
    }

    @MainActor
    func resume(onCompletion: @escaping @MainActor (Result<Void, Error>) -> Void) async -> Error? {
        let failure = await transitions.resume(onCompletion: onCompletion).value
        if failure != nil { await terminalCleanupTask?.value }
        return failure
    }

    @MainActor
    func stop() -> Task<Void, Never> {
        stopped = true
        let operation = transitions.stop()
        dismissPicker(self)
        resumeSelection(throwing: SpeechSessionError.screenCaptureSelectionCancelled)
        return Task {
            do {
                try await operation.value
            } catch {
                audio.discard()
            }
        }
    }

    func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        nonisolated(unsafe) let selectedFilter = filter
        nonisolated(unsafe) let updatedStream = stream
        Task { @MainActor [weak self] in
            guard let self, !self.stopped else { return }
            if let updatedStream {
                guard let current = self.transitions.stream as? NativeScreenCaptureStream,
                      current.stream === updatedStream else { return }
#if os(macOS) || targetEnvironment(macCatalyst)
                self.updateStream(current) { try await current.updateContentFilter(selectedFilter) }
                return
#endif
            }
            self.selectStream { [self] in
                let configuration = SCStreamConfiguration()
                configuration.capturesAudio = true
                configuration.sampleRate = Int(targetFormat.sampleRate)
                configuration.channelCount = Int(targetFormat.channelCount)
                configuration.excludesCurrentProcessAudio = options.excludesCurrentProcessAudio
                configuration.width = 2
                configuration.height = 2
                let capture = SCStream(filter: selectedFilter, configuration: configuration, delegate: self)
                try capture.addStreamOutput(self, type: .audio, sampleHandlerQueue: audio.queue)
                return NativeScreenCaptureStream(stream: capture, audio: audio)
            }
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor [weak self] in
            self?.resumeSelection(throwing: SpeechSessionError.screenCaptureSelectionCancelled)
        }
    }

    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let wrappedError = SpeechSessionError.screenCaptureFailed(error)
            if !self.resumeSelection(throwing: wrappedError) {
                _ = self.onTermination(wrappedError)
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor [weak self] in
            guard let self, let current = self.transitions.stream as? NativeScreenCaptureStream,
                  current.stream === stream else { return }
            self.streamDidStop(current, error: error)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        audio.receive(sampleBuffer, from: ObjectIdentifier(stream))
    }

    @discardableResult
    @MainActor
    func selectStream(makeStream: @escaping @MainActor () throws -> any ScreenCaptureStream) -> Task<Void, Never> {
        guard !stopped else { return Task {} }
        return observeSelection(transitions.replace(makeStream: makeStream))
    }

    @discardableResult
    @MainActor
    func updateStream(
        _ stream: any ScreenCaptureStream,
        operation: @escaping @MainActor () async throws -> Void
    ) -> Task<Void, Never> {
        guard !stopped, transitions.isCurrent(stream) else { return Task {} }
        let update = transitions.update(stream, operation: operation)
        let id = UUID()
        filterUpdateID = id
        return Task { @MainActor in
            do {
                try await update.value
            } catch {
                guard !self.stopped, self.filterUpdateID == id, self.transitions.isCurrent(stream) else { return }
                _ = self.onTermination(SpeechSessionError.screenCaptureFailed(error))
            }
        }
    }

    @MainActor
    private func observeSelection(_ operation: Task<Void, Error>) -> Task<Void, Never> {
        let id = UUID()
        pickerUpdateID = id
        return Task { @MainActor in
            do {
                try await operation.value
                guard !self.stopped, self.pickerUpdateID == id else { return }
                self.resumeSelection()
            } catch {
                guard !self.stopped, self.pickerUpdateID == id else { return }
                if !self.resumeSelection(throwing: error) {
                    _ = self.onTermination(SpeechSessionError.screenCaptureFailed(error))
                }
            }
        }
    }

    @discardableResult
    @MainActor
    private func resumeSelection(throwing error: Error? = nil) -> Bool {
        guard let selectionContinuation else { return false }
        self.selectionContinuation = nil
        if let error {
            selectionContinuation.resume(throwing: error)
        } else {
            selectionContinuation.resume()
        }
        return true
    }

    @MainActor
    func streamDidStop(_ stream: any ScreenCaptureStream, error: Error) {
        let nativeError = error as NSError
        let userStopped = nativeError.domain == SCStreamError.errorDomain
            && nativeError.code == SCStreamError.Code.userStopped.rawValue
        let failure: Error? = userStopped ? nil : SpeechSessionError.screenCaptureFailed(error)
        if let nativeStream = stream as? NativeScreenCaptureStream {
            audio.stop(ObjectIdentifier(nativeStream.stream), drain: userStopped)
        }
        let isCurrent = transitions.didStop(stream, error: failure)
        guard !stopped, isCurrent else { return }
        stopped = true
        terminalCleanupTask = onTermination(failure)
    }
}
#else
public extension SpeechSession {
    /// Placeholder options used when ScreenCaptureKit is unavailable to the current build target.
    struct ScreenCaptureTranscriptionOptions {
        public init() {}
    }

    /// Screen capture transcription requires ScreenCaptureKit.
    func startTranscribingScreenCapture(
        options: ScreenCaptureTranscriptionOptions = .init(),
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]? = nil
    ) -> AsyncThrowingStream<SpeechTranscriber.Result, Error> {
        _ = options
        _ = contextualStrings
        let (stream, continuation) = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()
        continuation.finish(throwing: SpeechSessionError.screenCaptureUnavailable)
        return stream
    }
}

@MainActor
extension SpeechSession {
    func pauseScreenCaptureStreamingIfNeeded(generation: Int) async {}

    func stopScreenCaptureStreamingIfNeeded() async {
        screenCaptureInputProvider = nil
    }
}
#endif
