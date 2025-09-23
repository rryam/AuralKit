import AVFoundation

// MARK: - Audio Streamer

class AudioStreamer: @unchecked Sendable {

    private let audioEngine = AVAudioEngine()

    /// Start the audio stream with a manager and converter
    func startStreaming(with manager: SpeechTranscriberManager, converter: BufferConverter) throws {
        audioEngine.inputNode.removeTap(onBus: 0)

        audioEngine.inputNode.installTap(onBus: 0,
                                         bufferSize: 4096,
                                         format: audioEngine.inputNode.outputFormat(forBus: 0)) { buffer, time in
            manager.processAudioBuffer(buffer, converter: converter)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    /// Stop the audio stream
    func stop() {
        audioEngine.stop()
    }
}
