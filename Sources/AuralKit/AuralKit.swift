import Foundation

// MARK: - Transcription Result

/// A single transcription result from the speech recognizer.
public struct TranscriptionResult {
    /// The transcribed text with timing metadata.
    public let text: AttributedString

    /// Whether this result is final or volatile (partial).
    public let isFinal: Bool

    public init(text: AttributedString, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

// MARK: - AuralKit

/// Wrapper for streaming live speech-to-text using the SpeechTranscriber/SpeechAnalyzer stack.
///
/// `AuralKit` hides the details of microphone capture, buffer conversion, model installation,
/// and result streaming. The API is designed around Swift Concurrency and integrates cleanly with
/// `for try await` loops.
///
/// ```swift
/// let kit = AuralKit(locale: .current)
///
/// Task {
///     do {
///         for try await transcript in kit.startTranscribing() {
///             print(String(transcript.characters))
///         }
///     } catch {
///         // Handle `AuralKitError`
///     }
/// }
/// ```
///
/// Call `stopTranscribing()` to end capture and unwind the stream. The same instance may be reused
/// for subsequent transcription sessions.
public final class AuralKit: @unchecked Sendable {

    // MARK: - Properties

    private let permissionsManager = PermissionsManager()
#if os(iOS)
    private let audioSessionManager = AudioSessionManager()
#endif
    private let transcriberManager = SpeechTranscriberManager()
    private let converter = BufferConverter()
    private let streamState = StreamState()

    @MainActor
    private lazy var audioStreamer = AudioStreamer()

    private let locale: Locale

    // MARK: - Init

    /// Create a new transcriber instance.
    ///
    /// - Parameter locale: Desired transcription locale. Defaults to the device locale and is
    ///   validated against `SpeechTranscriber.supportedLocales`. If the locale is not yet installed,
    ///   `AuralKit` automatically downloads the corresponding on-device model.
    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Progress of the ongoing model download, if any.
    ///
    /// Poll or observe this property to drive UI such as `ProgressView`. The value is non-nil only
    /// while a locale model is downloading.
    public var modelDownloadProgress: Progress? {
        transcriberManager.downloadProgress
    }

    // MARK: - Public API

    /// Start streaming live microphone audio to the speech analyzer.
    ///
    /// The returned `AsyncThrowingStream` yields `TranscriptionResult` chunks containing both text and
    /// timing metadata (`.audioTimeRange`), as well as whether the result is final or volatile (partial).
    /// Consume the stream with `for try await` and call `stopTranscribing()` to finish early.
    ///
    /// ```swift
    /// for try await result in kit.startTranscribing() {
    ///     if result.isFinal {
    ///         // Final result - accumulate this
    ///     } else {
    ///         // Volatile result - replace previous partial
    ///     }
    /// }
    /// ```
    public func startTranscribing() -> AsyncThrowingStream<TranscriptionResult, Error> {
        print("🎤 AuralKit: startTranscribing() called")
        let (stream, continuation) = AsyncThrowingStream<TranscriptionResult, Error>.makeStream()

        continuation.onTermination = { [weak self] termination in
            print("🎤 AuralKit: Stream terminated with reason: \(termination)")
            print("🎤 AuralKit: About to call cleanup from onTermination")
            Task {
                print("🎤 AuralKit: Inside termination cleanup task")
                await self?.cleanup(cancelRecognizer: true)
                print("🎤 AuralKit: Termination cleanup task complete")
            }
        }

        Task { [weak self] in
            guard let self else {
                print("🔴 AuralKit: Self is nil in startTranscribing task")
                return
            }

            print("🎤 AuralKit: Checking for active stream")
            if await self.streamState.hasActiveStream() {
                print("🔴 AuralKit: Already has active stream")
                continuation.finish(throwing: AuralKitError.recognitionStreamSetupFailed)
                return
            }

            print("🎤 AuralKit: Setting continuation and starting pipeline")
            await self.streamState.setContinuation(continuation)
            await self.startPipeline(with: continuation)
        }

        print("🎤 AuralKit: Returning stream")
        return stream
    }

    /// Stop capturing audio and finish the current transcription stream.
    ///
    /// Safe to call even if `startTranscribing()` has not been invoked or the stream has already
    /// completed; the method simply waits for cleanup and returns.
    public func stopTranscribing() async {
        print("🛑 AuralKit: stopTranscribing() called")
        await cleanup(cancelRecognizer: true)
        await finishStream(error: nil)
        print("🛑 AuralKit: stopTranscribing() completed")
    }

    // MARK: - Private helpers

    private func startPipeline(with continuation: AsyncThrowingStream<TranscriptionResult, Error>.Continuation) async {
        print("🔧 AuralKit: Starting pipeline")
        do {
            print("🔧 AuralKit: Ensuring permissions")
            try await permissionsManager.ensurePermissions()
            print("🔧 AuralKit: Permissions ensured")

#if os(iOS)
            print("🔧 AuralKit: Setting up audio session on iOS")
            try await MainActor.run {
                try audioSessionManager.setUpAudioSession()
            }
            print("🔧 AuralKit: Audio session setup complete")
#endif

            print("🔧 AuralKit: Setting up transcriber for locale \(locale.identifier)")
            let transcriber = try await transcriberManager.setUpTranscriber(locale: locale)
            print("🔧 AuralKit: Transcriber setup complete")

            print("🔧 AuralKit: Creating recognizer task")
            let recognizerTask = Task<Void, Never> { [weak self] in
                guard let self else {
                    print("🔴 AuralKit: Recognizer task - self is nil")
                    return
                }
                print("🔧 AuralKit: Recognizer task started")

                do {
                    print("🔧 AuralKit: Starting to iterate over transcriber results")
                    print("🔧 AuralKit: transcriber.results type: \(type(of: transcriber.results))")

                    var resultCount = 0
                    for try await result in transcriber.results {
                        resultCount += 1
                        print("🔧 AuralKit: Got transcriber result #\(resultCount): isFinal=\(result.isFinal), text=\(String(result.text.characters))")

                        let transcriptionResult = TranscriptionResult(
                            text: result.text,
                            isFinal: result.isFinal
                        )
                        continuation.yield(transcriptionResult)
                    }
                    print("🔧 AuralKit: Recognizer task completed normally after \(resultCount) results")
                    await self.finishFromRecognizerTask(error: nil)
                } catch is CancellationError {
                    print("🔧 AuralKit: Recognizer task cancelled")
                    // Cancellation handled by cleanup logic
                } catch {
                    print("🔴 AuralKit: Recognizer task error: \(error)")
                    print("🔴 AuralKit: Error type: \(type(of: error))")
                    await self.finishFromRecognizerTask(error: error)
                }
                print("🔧 AuralKit: Recognizer task is exiting")
            }

            await streamState.setRecognizerTask(recognizerTask)
            print("🔧 AuralKit: Recognizer task set")

            print("🔧 AuralKit: Starting audio streamer")
            // Audio processing happens in the tap callback in AudioStreamer
            // The tap callback directly calls transcriberManager.processAudioBuffer
            _ = try await MainActor.run { [self] in
                try audioStreamer.startStreaming(with: transcriberManager, converter: converter)
            }
            print("🔧 AuralKit: Audio streamer started")

            await streamState.markStreaming(true)
            print("🔧 AuralKit: Pipeline setup complete")
        } catch {
            print("🔴 AuralKit: Pipeline startup error: \(error)")
            await finishWithStartupError(error)
        }
    }

    private func finishWithStartupError(_ error: Error) async {
        await cleanup(cancelRecognizer: true)
        await finishStream(error: error)
    }

    private func finishFromRecognizerTask(error: Error?) async {
        print("🔧 AuralKit: finishFromRecognizerTask called with error: \(String(describing: error))")
        await cleanup(cancelRecognizer: false)
        await finishStream(error: error)
    }

    private func cleanup(cancelRecognizer: Bool) async {
        print("🧹 AuralKit: cleanup called with cancelRecognizer: \(cancelRecognizer)")
        let recognizerTask = await streamState.takeRecognizerTask()
        if cancelRecognizer {
            print("🧹 AuralKit: Cancelling recognizer task")
            recognizerTask?.cancel()
        }

        await streamState.markStreaming(false)
        print("🧹 AuralKit: Marked streaming as false")

        print("🧹 AuralKit: Stopping audio streamer")
        await MainActor.run { [self] in
            audioStreamer.stop()
        }
        print("🧹 AuralKit: Audio streamer stopped")

        print("🧹 AuralKit: Stopping transcriber manager")
        await transcriberManager.stop()
        print("🧹 AuralKit: Cleanup complete")
    }

    private func finishStream(error: Error?) async {
        guard let continuation = await streamState.takeContinuation() else { return }

        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}

// MARK: - Stream State Actor

private actor StreamState {
    private var continuation: AsyncThrowingStream<TranscriptionResult, Error>.Continuation?
    private var recognizerTask: Task<Void, Never>?
    private var isStreaming = false

    func hasActiveStream() -> Bool {
        continuation != nil || recognizerTask != nil || isStreaming
    }

    func setContinuation(_ continuation: AsyncThrowingStream<TranscriptionResult, Error>.Continuation) {
        self.continuation = continuation
    }

    func takeContinuation() -> AsyncThrowingStream<TranscriptionResult, Error>.Continuation? {
        defer { continuation = nil }
        return continuation
    }

    func setRecognizerTask(_ task: Task<Void, Never>?) {
        recognizerTask = task
    }

    func takeRecognizerTask() -> Task<Void, Never>? {
        defer { recognizerTask = nil }
        return recognizerTask
    }

    func markStreaming(_ streaming: Bool) {
        isStreaming = streaming
    }
}
