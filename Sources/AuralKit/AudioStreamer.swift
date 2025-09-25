import Foundation
import AVFoundation

// MARK: - Audio Streamer

class AudioStreamer: @unchecked Sendable {

    private let audioEngine = AVAudioEngine()
    private var continuation: AsyncThrowingStream<Void, Error>.Continuation?

    /// Start the audio stream with a manager and converter.
    /// Returns an async stream that completes when the stream stops, or throws if streaming fails.
    func startStreaming(with manager: SpeechTranscriberManager,
                        converter: BufferConverter) throws -> AsyncThrowingStream<Void, Error> {
        guard continuation == nil else {
            throw AuralKitError.recognitionStreamSetupFailed
        }

        let (stream, continuation) = AsyncThrowingStream<Void, Error>.makeStream()
        self.continuation = continuation

        audioEngine.inputNode.removeTap(onBus: 0)

        audioEngine.inputNode.installTap(onBus: 0,
                                         bufferSize: 4096,
                                         format: audioEngine.inputNode.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            guard let self else { return }

            do {
                try manager.processAudioBuffer(buffer, converter: converter)
            } catch {
                self.finishStreaming(with: error)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            audioEngine.inputNode.removeTap(onBus: 0)
            finishStreaming(with: error)
            throw error
        }

        continuation.onTermination = { [weak self] _ in
            self?.stop()
        }

        return stream
    }

    /// Stop the audio stream
    func stop() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        finishStreaming(with: nil)
    }

    private func finishStreaming(with error: Error?) {
        guard let continuation else { return }
        self.continuation = nil

        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}
