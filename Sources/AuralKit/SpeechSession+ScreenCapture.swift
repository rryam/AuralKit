import AVFoundation
import CoreMedia
import Foundation
import Speech

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
        continuation = .speech(newContinuation)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.startScreenCapturePipeline(
                with: newContinuation,
                options: options,
                contextualStrings: contextualStrings
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
        contextualStrings: [AnalysisContext.ContextualStringsTag: [String]]?
    ) async {
        do {
            if Self.shouldLog(.notice) {
                Self.logger.notice("Starting screen capture pipeline setup")
            }

            try await ensureSpeechRecognitionAuthorization(context: "for screen capture transcription")
            let transcriber = try await setUpSpeechTranscriber(contextualStrings: contextualStrings)
            recognizerTask = createSpeechRecognizerTask(
                transcriber: transcriber,
                streamContinuation: streamContinuation
            )
            try await setUpScreenCaptureStreaming(options: options)

            streamingMode = .screenCapture
            setStatus(.transcribing)
            activeResultKind = .speech
            if Self.shouldLog(.info) {
                Self.logger.info("Pipeline started (mode: screen capture)")
            }
        } catch {
            if Self.shouldLog(.error) {
                Self.logger.error("Screen capture pipeline failed: \(error.localizedDescription, privacy: .public)")
            }
            await finishWithStartupError(error)
        }
    }

    func setUpScreenCaptureStreaming(options: ScreenCaptureTranscriptionOptions) async throws {
        guard let analyzerFormat, let inputBuilder else {
            throw SpeechSessionError.invalidAudioDataType
        }

        let provider = ScreenCaptureAudioInputProvider(
            options: options,
            targetFormat: analyzerFormat,
            inputContinuation: inputBuilder,
            onFailure: { [weak self] error in
                Task { @MainActor [weak self] in
                    await self?.finishFromRecognizerTask(error: error)
                }
            }
        )
        screenCaptureInputProvider = provider
        try await provider.start()
    }
}

@MainActor
extension SpeechSession {
    func pauseScreenCaptureStreamingIfNeeded() async {
        guard #available(iOS 27.0, macOS 14.0, *) else { return }
        guard let provider = screenCaptureInputProvider as? ScreenCaptureAudioInputProvider else { return }
        await provider.pause()
    }

    func resumeScreenCaptureStreamingIfNeeded() async throws {
        guard #available(iOS 27.0, macOS 14.0, *) else {
            throw SpeechSessionError.screenCaptureUnavailable
        }
        guard let provider = screenCaptureInputProvider as? ScreenCaptureAudioInputProvider else {
            throw SpeechSessionError.recognitionStreamSetupFailed
        }
        try await provider.resume()
    }

    func stopScreenCaptureStreamingIfNeeded() async {
        guard #available(iOS 27.0, macOS 14.0, *) else {
            screenCaptureInputProvider = nil
            return
        }
        guard let provider = screenCaptureInputProvider as? ScreenCaptureAudioInputProvider else {
            screenCaptureInputProvider = nil
            return
        }
        await provider.stop()
        screenCaptureInputProvider = nil
    }
}

@available(iOS 27.0, macOS 14.0, *)
private final class ScreenCaptureAudioInputProvider: NSObject, SCStreamOutput, SCStreamDelegate,
    SCContentSharingPickerObserver, @unchecked Sendable {

    private let options: SpeechSession.ScreenCaptureTranscriptionOptions
    private let targetFormat: AVAudioFormat
    private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    private let onFailure: @Sendable (Error) -> Void
    private let sampleQueue = DispatchQueue(label: "com.auralkit.screencapture.audio", qos: .userInitiated)
    private let audioProcessingActor = AudioProcessingActor()

    private var stream: SCStream?
    private var selectionContinuation: CheckedContinuation<Void, Error>?
    private var isRunning = false
    private var intentionallyStoppingStreams = Set<ObjectIdentifier>()

    init(
        options: SpeechSession.ScreenCaptureTranscriptionOptions,
        targetFormat: AVAudioFormat,
        inputContinuation: AsyncStream<AnalyzerInput>.Continuation,
        onFailure: @escaping @Sendable (Error) -> Void
    ) {
        self.options = options
        self.targetFormat = targetFormat
        self.inputContinuation = inputContinuation
        self.onFailure = onFailure
        super.init()
    }

    @MainActor
    func start() async throws {
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
    }

    @MainActor
    func pause() async {
        guard isRunning, let stream else { return }
        markStreamForIntentionalStop(stream)
        try? await stream.stopCapture()
        isRunning = false
    }

    @MainActor
    func resume() async throws {
        guard !isRunning, let stream else {
            throw SpeechSessionError.recognitionStreamSetupFailed
        }
        try await stream.startCapture()
        isRunning = true
    }

    @MainActor
    func stop() async {
        let picker = SCContentSharingPicker.shared
        picker.isActive = false
        picker.remove(self)

        if let selectionContinuation {
            selectionContinuation.resume(throwing: SpeechSessionError.screenCaptureSelectionCancelled)
            self.selectionContinuation = nil
        }

        if isRunning, let stream {
            markStreamForIntentionalStop(stream)
            try? await stream.stopCapture()
        }
        stream = nil
        isRunning = false
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        nonisolated(unsafe) let selectedFilter = filter
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await beginCapture(with: selectedFilter)
                resumeSelection()
            } catch {
                resumeSelection(throwing: error)
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
            self?.resumeSelection(throwing: SpeechSessionError.screenCaptureFailed(error))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor [weak self] in
            guard let self, !self.consumeIntentionalStop(for: stream) else { return }
            self.isRunning = false
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

    @MainActor
    private func beginCapture(with filter: SCContentFilter) async throws {
        if isRunning, let stream {
            markStreamForIntentionalStop(stream)
            try await stream.stopCapture()
            isRunning = false
        }

        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.capturesAudio = true
        streamConfiguration.sampleRate = Int(targetFormat.sampleRate)
        streamConfiguration.channelCount = Int(targetFormat.channelCount)
        streamConfiguration.excludesCurrentProcessAudio = options.excludesCurrentProcessAudio
        streamConfiguration.width = 2
        streamConfiguration.height = 2

        let captureStream = SCStream(filter: filter, configuration: streamConfiguration, delegate: self)
        try captureStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        self.stream = captureStream
        try await captureStream.startCapture()
        isRunning = true
    }

    @MainActor
    private func resumeSelection(throwing error: Error? = nil) {
        guard let selectionContinuation else { return }
        self.selectionContinuation = nil
        if let error {
            selectionContinuation.resume(throwing: error)
        } else {
            selectionContinuation.resume()
        }
    }

    private func makeSourceFormat(from sampleBuffer: CMSampleBuffer) -> AVAudioFormat? {
        guard let formatDescription = sampleBuffer.formatDescription,
              var sourceDescription = formatDescription.audioStreamBasicDescription else {
            return nil
        }

        return AVAudioFormat(streamDescription: &sourceDescription)
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let sendableBuffer = SpeechSession.SendablePCMBuffer(buffer: buffer)
        Task { [audioProcessingActor, inputContinuation, onFailure, targetFormat] in
            do {
                let input = try await audioProcessingActor.makeAnalyzerInput(
                    from: sendableBuffer,
                    analyzerFormat: targetFormat
                )
                inputContinuation.yield(input)
            } catch {
                onFailure(error)
            }
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

@MainActor
extension SpeechSession {
    func pauseScreenCaptureStreamingIfNeeded() async {}

    func resumeScreenCaptureStreamingIfNeeded() async throws {
        throw SpeechSessionError.screenCaptureUnavailable
    }

    func stopScreenCaptureStreamingIfNeeded() async {
        screenCaptureInputProvider = nil
    }
}
#endif
