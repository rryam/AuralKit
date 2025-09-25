import Foundation
import AVFoundation

// MARK: - Audio Streamer

actor AudioStreamer {

    @MainActor
    private let audioEngine = AVAudioEngine()
    private var continuation: AsyncThrowingStream<Void, Error>.Continuation?

    /// Start the audio stream with a manager and converter.
    /// Returns an async stream that completes when the stream stops or throws if streaming fails.
    func startStreaming(with manager: SpeechTranscriberManager,
                        converter: BufferConverter) async throws -> AsyncThrowingStream<Void, Error> {
        guard continuation == nil else {
            throw AuralKitError.recognitionStreamSetupFailed
        }

        let (stream, continuation) = AsyncThrowingStream<Void, Error>.makeStream()
        self.continuation = continuation

        await MainActor.run {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.inputNode.installTap(onBus: 0,
                                             bufferSize: 4096,
                                             format: audioEngine.inputNode.outputFormat(forBus: 0)) { [weak manager] buffer, _ in
                guard let manager else { return }

                do {
                    try manager.processAudioBuffer(buffer, converter: converter)
                } catch {
                    Task { [weak self] in
                        guard let self else { return }
                        await self.handleStreamingFailure(error)
                    }
                }
            }
            audioEngine.prepare()
        }

        do {
            try await MainActor.run {
                try audioEngine.start()
            }
        } catch {
            await handleStreamingFailure(error)
            throw error
        }

        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.stop() }
        }

        return stream
    }

    /// Stop the audio stream
    func stop() async {
        await stopEngine()
        await finishStreaming(with: nil)
    }

    private func handleStreamingFailure(_ error: Error) async {
        await stopEngine()
        await finishStreaming(with: error)
    }

    private func stopEngine() async {
        await MainActor.run {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
    }

    private func finishStreaming(with error: Error?) async {
        guard let continuation else { return }
        self.continuation = nil

        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}
