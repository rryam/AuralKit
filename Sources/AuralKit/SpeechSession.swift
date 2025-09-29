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

    // MARK: - Properties

    private let permissionsManager = PermissionsManager()
    private let transcriberManager = SpeechTranscriberManager()
    private let converter = BufferConverter()
    private let streamState = StreamState()

    private lazy var audioEngine = AVAudioEngine()
    private var isAudioStreaming = false

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
    ///
    /// ```swift
    /// let session = SpeechSession()
    /// if let progress = session.modelDownloadProgress {
    ///     print("Downloading: \(progress.fractionCompleted * 100)%")
    /// }
    /// ```
    public var modelDownloadProgress: Progress? {
        transcriberManager.downloadProgress
    }

    // MARK: - Public API

    /// Start streaming live microphone audio to the speech analyzer.
    ///
    /// The returned `AsyncThrowingStream` yields `SpeechTranscriber.Result` chunks containing both text and
    /// timing metadata (`.audioTimeRange`), as well as whether the result is final or volatile (partial).
    /// Consume the stream with `for try await` and call `stopTranscribing()` to finish early.
    ///
    /// ```swift
    /// for try await result in session.startTranscribing() {
    ///     if result.isFinal {
    ///         // Final result - accumulate this
    ///     } else {
    ///         // Volatile result - replace previous partial
    ///     }
    /// }
    /// ```
    public func startTranscribing() -> AsyncThrowingStream<SpeechTranscriber.Result, Error> {
        let (stream, continuation) = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()

        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.cleanup(cancelRecognizer: true)
            }
        }

        Task { [weak self] in
            guard let self else { return }

            if await self.streamState.hasActiveStream() {
                continuation.finish(throwing: SpeechSessionError.recognitionStreamSetupFailed)
                return
            }

            await self.streamState.setContinuation(continuation)
            await self.startPipeline(with: continuation)
        }

        return stream
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

    private func startPipeline(with continuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation) async {
        do {
            try await permissionsManager.ensurePermissions()

#if os(iOS)
            try await MainActor.run {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, mode: .spokenAudio)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            }
#endif

            let transcriber = try await transcriberManager.setUpTranscriber(locale: locale)

            let recognizerTask = Task<Void, Never> { [weak self] in
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

            await streamState.setRecognizerTask(recognizerTask)

            try startAudioStreaming()

            await streamState.markStreaming(true)
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
        let recognizerTask = await streamState.takeRecognizerTask()
        if cancelRecognizer {
            recognizerTask?.cancel()
        }

        await streamState.markStreaming(false)
        stopAudioStreaming()
        await transcriberManager.stop()
    }

    private func finishStream(error: Error?) async {
        guard let continuation = await streamState.takeContinuation() else { return }

        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
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
                                         format: inputFormat) { [transcriberManager, converter] buffer, _ in
            do {
                try transcriberManager.processAudioBuffer(buffer, converter: converter)
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
}

// MARK: - Stream State Actor

private actor StreamState {
    private var continuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation?
    private var recognizerTask: Task<Void, Never>?
    private var isStreaming = false

    func hasActiveStream() -> Bool {
        continuation != nil || recognizerTask != nil || isStreaming
    }

    func setContinuation(_ continuation: AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation) {
        self.continuation = continuation
    }

    func takeContinuation() -> AsyncThrowingStream<SpeechTranscriber.Result, Error>.Continuation? {
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
