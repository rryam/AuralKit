import Foundation
import AVFoundation

// MARK: - Audio Streamer

@MainActor
final class AudioStreamer {

    private let audioEngine = AVAudioEngine()
    private var continuation: AsyncThrowingStream<Void, Error>.Continuation?

    /// Start the audio stream with a manager and converter.
    /// Returns an async stream that completes when the stream stops or throws if streaming fails.
    func startStreaming(with manager: SpeechTranscriberManager,
                        converter: BufferConverter) throws -> AsyncThrowingStream<Void, Error> {
        print("🎵 AudioStreamer: startStreaming called")

        guard continuation == nil else {
            print("🔴 AudioStreamer: Already has continuation")
            throw SpeechSessionError.recognitionStreamSetupFailed
        }

        print("🎵 AudioStreamer: Creating stream")
        let (stream, continuation) = AsyncThrowingStream<Void, Error>.makeStream()
        self.continuation = continuation

        print("🎵 AudioStreamer: Setting up audio engine - removing existing tap")
        audioEngine.inputNode.removeTap(onBus: 0)
        print("🎵 AudioStreamer: Installing new audio tap")
        audioEngine.inputNode.installTap(onBus: 0,
                                         bufferSize: 4096,
                                         format: audioEngine.inputNode.outputFormat(forBus: 0)) { [weak manager] buffer, _ in
            guard let manager else { return }

            do {
                try manager.processAudioBuffer(buffer, converter: converter)
            } catch {
                print("🔴 AudioStreamer: Audio processing error: \(error)")
                // Handle streaming failure on main actor
                Task { @MainActor [weak self] in
                    self?.handleStreamingFailure(error)
                }
            }
        }
        print("🎵 AudioStreamer: Preparing audio engine")
        audioEngine.prepare()
        print("🎵 AudioStreamer: Audio engine prepared")

        do {
            print("🎵 AudioStreamer: Starting audio engine")
            try audioEngine.start()
            print("🎵 AudioStreamer: Audio engine started successfully")
        } catch {
            print("🔴 AudioStreamer: Failed to start audio engine: \(error)")
            handleStreamingFailure(error)
            throw error
        }

        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.stop()
            }
        }

        print("🎵 AudioStreamer: Returning stream")
        return stream
    }

    /// Stop the audio stream
    func stop() {
        print("🎵 AudioStreamer: stop() called")
        stopEngine()
        finishStreaming(with: nil)
    }

    private func handleStreamingFailure(_ error: Error) {
        print("🔴 AudioStreamer: handleStreamingFailure called with: \(error)")
        stopEngine()
        finishStreaming(with: error)
    }

    private func stopEngine() {
        print("🎵 AudioStreamer: stopEngine() - removing tap and stopping")
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        print("🎵 AudioStreamer: Audio engine stopped")
    }

    private func finishStreaming(with error: Error?) {
        print("🎵 AudioStreamer: finishStreaming called")
        guard let continuation else {
            print("🎵 AudioStreamer: No continuation to finish")
            return
        }
        self.continuation = nil

        if let error {
            print("🎵 AudioStreamer: Finishing stream with error: \(error)")
            continuation.finish(throwing: error)
        } else {
            print("🎵 AudioStreamer: Finishing stream successfully")
            continuation.finish()
        }
    }
}
