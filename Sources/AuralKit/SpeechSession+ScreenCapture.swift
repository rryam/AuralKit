import AVFoundation
import CoreMedia
import Foundation
import Speech

// swiftlint:disable file_length

/// Internal capture lifetime boundary; production uses ScreenCaptureKit below.
@available(iOS 26.0, macOS 14.0, *)
protocol ScreenCaptureInput: AnyObject {
    @MainActor func start() async throws
    @MainActor func pause() async
    @MainActor func resume() async throws
    @MainActor func resumeOutcome() async -> ScreenCaptureResumeOutcome
    @MainActor func stop() async
}

@available(iOS 26.0, macOS 14.0, *)
extension ScreenCaptureInput {
    @MainActor
    func resumeOutcome() async -> ScreenCaptureResumeOutcome {
        do {
            try await resume()
            return ScreenCaptureResumeOutcome(isCurrent: { true }, error: nil)
        } catch {
            return ScreenCaptureResumeOutcome(isCurrent: { true }, error: error)
        }
    }
}

@available(iOS 26.0, macOS 14.0, *)
extension SpeechSession {
    func pauseScreenCaptureStreamingIfNeeded() async {
        await screenCaptureInputProvider?.pause()
    }

    func resumeScreenCaptureStreamingIfNeeded() async throws -> ScreenCaptureResumeOutcome {
        guard let provider = screenCaptureInputProvider else {
            throw SpeechSessionError.recognitionStreamSetupFailed
        }
        return await provider.resumeOutcome()
    }

    func stopScreenCaptureStreamingIfNeeded() async {
        let provider = screenCaptureInputProvider
        screenCaptureInputProvider = nil
        await provider?.stop()
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
    /// audio as `CMSampleBuffer` values. AuralKit configures the stream for audio capture, converts
    /// incoming audio samples into analyzer-compatible `AVAudioPCMBuffer`s, and emits normal
    /// `SpeechTranscriber.Result` values.
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
        newContinuation.onTermination = { [weak self] _ in
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
            if let hooks = screenCapturePipelineHooks {
                try await hooks.authorize()
                try Task.checkCancellation()
                let prepared = try await hooks.prepareAnalysis()
                analyzerFormat = prepared.format
                inputBuilder = prepared.inputs
                screenCaptureAnalysisFinalizer = prepared.finalize
            } else {
                try await ensureSpeechRecognitionAuthorization(context: "for screen capture transcription")
                try Task.checkCancellation()
                let transcriber = try await setUpSpeechTranscriber(contextualStrings: contextualStrings)
                try Task.checkCancellation()
                recognizerTask = createSpeechRecognizerTask(
                    transcriber: transcriber,
                    streamContinuation: streamContinuation,
                    generation: generation
                )
            }
            try Task.checkCancellation()
            try await setUpScreenCaptureStreaming(options: options, generation: generation)
            try Task.checkCancellation()

            streamingMode = .screenCapture
            setStatus(.transcribing)
            activeResultKind = .speech
            if Self.shouldLog(.info) {
                Self.logger.info("Pipeline started (mode: screen capture)")
            }
        } catch is CancellationError {
            pipelineTask = nil
            await finishCancelledPipelineSetup(generation: generation)
        } catch {
            if Self.shouldLog(.error) {
                Self.logger.error("Screen capture pipeline failed: \(error.localizedDescription, privacy: .public)")
            }
            pipelineTask = nil
            await finishWithStartupError(error, generation: generation)
        }
    }

    func setUpScreenCaptureStreaming(options: ScreenCaptureTranscriptionOptions, generation: Int) async throws {
        guard let analyzerFormat, let inputBuilder else {
            throw SpeechSessionError.invalidAudioDataType
        }

        let onFailure: @Sendable (Error) -> Void = { [weak self] error in
            Task { @MainActor [weak self] in
                await self?.finishFromRecognizerTask(error: error, generation: generation)
            }
        }
        let provider: any ScreenCaptureInput
        if let makeProvider = screenCapturePipelineHooks?.makeProvider {
            provider = makeProvider(analyzerFormat, inputBuilder, onFailure)
        } else {
            provider = ScreenCaptureAudioInputProvider(
                options: options, targetFormat: analyzerFormat,
                inputContinuation: inputBuilder, onFailure: onFailure
            )
        }
        screenCaptureInputProvider = provider
        try await provider.start()
    }
}

/// Keeps ScreenCaptureKit calls on the same tested transition boundary.
@available(iOS 27.0, macOS 14.0, *)
@MainActor
private final class NativeScreenCaptureStream: ScreenCaptureStream {
    let stream: SCStream
    let willStop: @MainActor (SCStream) -> Void

    init(stream: SCStream, willStop: @escaping @MainActor (SCStream) -> Void) {
        self.stream = stream
        self.willStop = willStop
    }

    func startCapture() async throws { try await stream.startCapture() }
    func stopCapture() async throws {
        willStop(stream)
        try await stream.stopCapture()
    }
}

@available(iOS 27.0, macOS 14.0, *)
final class ScreenCaptureAudioInputProvider: NSObject, ScreenCaptureInput, SCStreamOutput, SCStreamDelegate,
    SCContentSharingPickerObserver, @unchecked Sendable {

    private let options: SpeechSession.ScreenCaptureTranscriptionOptions
    private let targetFormat: AVAudioFormat
    private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    private let onFailure: @Sendable (Error) -> Void
    private let sampleQueue = DispatchQueue(label: "com.auralkit.screencapture.audio", qos: .userInitiated)
    // Only touched on `sampleQueue`, which serializes access.
    private let bufferConverter = BufferConverter()

    @MainActor private let transitions: ScreenCaptureTransitions
    private let presentPicker: @MainActor (ScreenCaptureAudioInputProvider) -> Void
    private let dismissPicker: @MainActor (any SCContentSharingPickerObserver) -> Void
    private var selectionContinuation: CheckedContinuation<Void, Error>?
    private var stopped = false
    @MainActor private var captureTasks: [UUID: Task<Void, Never>] = [:]
    @MainActor private var pickerUpdateID: UUID?
    private var intentionallyStoppingStreams = Set<ObjectIdentifier>()

    @MainActor
    init(
        options: SpeechSession.ScreenCaptureTranscriptionOptions,
        targetFormat: AVAudioFormat,
        inputContinuation: AsyncStream<AnalyzerInput>.Continuation,
        onFailure: @escaping @Sendable (Error) -> Void,
        transitions: ScreenCaptureTransitions = ScreenCaptureTransitions(),
        presentPicker: @escaping @MainActor (ScreenCaptureAudioInputProvider) -> Void = { provider in
            let picker = SCContentSharingPicker.shared
            let configuration = SCContentSharingPickerConfiguration()
            picker.configuration = configuration
            picker.defaultConfiguration = configuration
            picker.add(provider)
            picker.isActive = true
            picker.present()
        },
        dismissPicker: @escaping @MainActor (any SCContentSharingPickerObserver) -> Void = { observer in
            let picker = SCContentSharingPicker.shared
            picker.isActive = false
            picker.remove(observer)
        }
    ) {
        self.options = options
        self.targetFormat = targetFormat
        self.inputContinuation = inputContinuation
        self.onFailure = onFailure
        self.transitions = transitions
        self.presentPicker = presentPicker
        self.dismissPicker = dismissPicker
        super.init()
    }

    @MainActor
    func start() async throws {
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
        // Cleanup stops this provider before finalizing detached analyzer state.
        // stop() resumes pending selection and joins admitted picker updates.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            selectionContinuation = continuation
            presentPicker(self)
        }
        try Task.checkCancellation()
    }

    @MainActor
    func pause() async {
        _ = try? await transitions.pause().value
    }

    @MainActor
    func resume() async throws {
        guard !stopped else { throw CancellationError() }
        let outcome = await resumeOutcome()
        guard outcome.isCurrent() else { return }
        if let error = outcome.error { throw error }
    }

    @MainActor
    func resumeOutcome() async -> ScreenCaptureResumeOutcome {
        await transitions.resume().value
    }

    @MainActor
    func stop() async {
        stopped = true
        dismissPicker(self)

        if let selectionContinuation {
            selectionContinuation.resume(throwing: SpeechSessionError.screenCaptureSelectionCancelled)
            self.selectionContinuation = nil
        }

        // Joins internal start/resume/pause/replacement operations, including a late
        // start's compensating stop, before cleanup can finalize detached analyzer/model owners.
        _ = try? await transitions.stop().value
        let tasks = Array(captureTasks.values)
        for task in tasks { await task.value }
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
                guard (self.transitions.stream as? NativeScreenCaptureStream)?.stream === updatedStream else { return }
            }
            self.selectStream { [self] in
                let streamConfiguration = SCStreamConfiguration()
                streamConfiguration.capturesAudio = true
                streamConfiguration.sampleRate = Int(targetFormat.sampleRate)
                streamConfiguration.channelCount = Int(targetFormat.channelCount)
                streamConfiguration.excludesCurrentProcessAudio = options.excludesCurrentProcessAudio
                streamConfiguration.width = 2
                streamConfiguration.height = 2

                let captureStream = SCStream(filter: selectedFilter, configuration: streamConfiguration, delegate: self)
                try captureStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
                return NativeScreenCaptureStream(stream: captureStream) { [weak self] stream in
                    self?.markStreamForIntentionalStop(stream)
                }
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
                self.onFailure(wrappedError)
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor [weak self] in
            guard let self, !self.consumeIntentionalStop(for: stream),
                  !self.stopped,
                  (self.transitions.stream as? NativeScreenCaptureStream)?.stream === stream else { return }
            self.onFailure(SpeechSessionError.screenCaptureFailed(error))
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }
        guard let sourceFormat = makeSourceFormat(from: sampleBuffer) else { return }

        do {
            try sampleBuffer.withAudioBufferList { audioBufferList, _ in
                guard let sourceBuffer = AVAudioPCMBuffer(
                    pcmFormat: sourceFormat,
                    bufferListNoCopy: audioBufferList.unsafePointer
                ) else { return }

                guard let bufferCopy = sourceBuffer.copy() as? AVAudioPCMBuffer else {
                    onFailure(SpeechSessionError.conversionBufferCreationFailed)
                    return
                }

                processAudioBuffer(bufferCopy)
            }
        } catch {
            onFailure(SpeechSessionError.screenCaptureFailed(error))
        }
    }

    /// Common admission for the native picker callback and controlled capture collaborators.
    @MainActor
    func selectStream(makeStream: @escaping @MainActor () throws -> any ScreenCaptureStream) {
        guard !stopped else { return }
        let operation = transitions.replace(makeStream: makeStream)
        let id = UUID()
        self.pickerUpdateID = id
        self.captureTasks[id] = Task { @MainActor in
            defer { self.captureTasks[id] = nil }
            guard !self.stopped, self.pickerUpdateID == id else { return }
            do {
                try await operation.value
                guard !self.stopped, self.pickerUpdateID == id else { return }
                self.resumeSelection()
            } catch {
                guard !self.stopped, self.pickerUpdateID == id else { return }
                if !self.resumeSelection(throwing: error) {
                    self.onFailure(SpeechSessionError.screenCaptureFailed(error))
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

    private func makeSourceFormat(from sampleBuffer: CMSampleBuffer) -> AVAudioFormat? {
        guard let formatDescription = sampleBuffer.formatDescription,
              var sourceDescription = formatDescription.audioStreamBasicDescription else {
            return nil
        }

        return AVAudioFormat(streamDescription: &sourceDescription)
    }

    /// Convert and forward a captured buffer synchronously on `sampleQueue`.
    ///
    /// Inline conversion preserves capture order for the analyzer; the caller passes an
    /// already-copied buffer, so a passthrough conversion is safe to forward directly.
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        do {
            let converted = try bufferConverter.convertBuffer(buffer, to: targetFormat)
            inputContinuation.yield(AnalyzerInput(buffer: converted))
        } catch {
            onFailure(error)
        }
    }

    @MainActor
    private func markStreamForIntentionalStop(_ stream: SCStream) {
        intentionallyStoppingStreams.insert(ObjectIdentifier(stream))
    }

    @MainActor
    private func consumeIntentionalStop(for stream: SCStream) -> Bool {
        intentionallyStoppingStreams.remove(ObjectIdentifier(stream)) != nil
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

#endif
