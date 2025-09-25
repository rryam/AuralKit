import Foundation

// MARK: - AuralKit

@available(iOS 26.0, macOS 26.0, *)
public final class AuralKit: @unchecked Sendable {

    // MARK: - Properties

    private let permissionsManager = PermissionsManager()
#if os(iOS)
    private let audioSessionManager = AudioSessionManager()
#endif
    private let audioStreamer = AudioStreamer()
    private let transcriberManager = SpeechTranscriberManager()
    private let converter = BufferConverter()
    private let streamState = StreamState()

    private let locale: Locale

    // MARK: - Init

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    // MARK: - Public API

    /// Start transcribing
    public func startTranscribing() -> AsyncThrowingStream<AttributedString, Error> {
        let (stream, continuation) = AsyncThrowingStream<AttributedString, Error>.makeStream()

        continuation.onTermination = { [weak self] _ in
            Task { await self?.cleanup(cancelRecognizer: true) }
        }

        Task { [weak self] in
            guard let self else { return }

            if await self.streamState.hasActiveStream() {
                continuation.finish(throwing: AuralKitError.recognitionStreamSetupFailed)
                return
            }

            await self.streamState.setContinuation(continuation)
            await self.startPipeline(with: continuation)
        }

        return stream
    }

    /// Stop transcribing
    public func stopTranscribing() async {
        await cleanup(cancelRecognizer: true)
        await finishStream(error: nil)
    }

    // MARK: - Private helpers

    private func startPipeline(with continuation: AsyncThrowingStream<AttributedString, Error>.Continuation) async {
        do {
            try await permissionsManager.ensurePermissions()

#if os(iOS)
            try await MainActor.run {
                try audioSessionManager.setUpAudioSession()
            }
#endif

            let transcriber = try await transcriberManager.setUpTranscriber(locale: locale)

            let recognizerTask = Task<Void, Never> { [weak self] in
                guard let self else { return }

                do {
                    for try await result in transcriber.results {
                        continuation.yield(result.text)
                    }
                    await self.finishFromRecognizerTask(error: nil)
                } catch is CancellationError {
                    // Cancellation handled by cleanup logic
                } catch {
                    await self.finishFromRecognizerTask(error: error)
                }
            }

            await streamState.setRecognizerTask(recognizerTask)

            let streamingStream = try await MainActor.run {
                try audioStreamer.startStreaming(with: transcriberManager,
                                                 converter: converter)
            }

            let streamingTask = Task<Void, Never> { [weak self] in
                guard let self else { return }
                do {
                    for try await _ in streamingStream {}
                } catch is CancellationError {
                    return
                } catch {
                    await self.finishWithStreamingError(error)
                }
            }

            await streamState.setStreamingTask(streamingTask)
            await streamState.markStreaming(true)
        } catch {
            await finishWithStartupError(error)
        }
    }

    private func finishWithStartupError(_ error: Error) async {
        await cleanup(cancelRecognizer: true)
        await finishStream(error: error)
    }

    private func finishWithStreamingError(_ error: Error) async {
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

        let streamingTask = await streamState.takeStreamingTask()
        streamingTask?.cancel()

        await streamState.markStreaming(false)

        await MainActor.run {
            audioStreamer.stop()
        }

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
}

// MARK: - Stream State Actor

@available(iOS 26.0, macOS 26.0, *)
private actor StreamState {
    private var continuation: AsyncThrowingStream<AttributedString, Error>.Continuation?
    private var recognizerTask: Task<Void, Never>?
    private var streamingTask: Task<Void, Never>?
    private var isStreaming = false

    func hasActiveStream() -> Bool {
        continuation != nil || recognizerTask != nil || streamingTask != nil || isStreaming
    }

    func setContinuation(_ continuation: AsyncThrowingStream<AttributedString, Error>.Continuation) {
        self.continuation = continuation
    }

    func takeContinuation() -> AsyncThrowingStream<AttributedString, Error>.Continuation? {
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

    func setStreamingTask(_ task: Task<Void, Never>?) {
        streamingTask = task
    }

    func takeStreamingTask() -> Task<Void, Never>? {
        defer { streamingTask = nil }
        return streamingTask
    }

    func markStreaming(_ streaming: Bool) {
        isStreaming = streaming
    }
}
