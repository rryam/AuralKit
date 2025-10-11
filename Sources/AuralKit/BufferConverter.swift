@preconcurrency import AVFoundation

// MARK: - Buffer Converter (from Apple's sample)

class BufferConverter: @unchecked Sendable {
    private var converter: AVAudioConverter?

    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else {
            return buffer
        }

        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            // Sacrifice quality of first samples to avoid timestamp drift from source
            converter?.primeMethod = .none
        }

        guard let converter else {
            throw SpeechSessionError.bufferConverterCreationFailed
        }

        let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let scaledInputFrameLength = Double(buffer.frameLength) * sampleRateRatio
        let frameCapacity = AVAudioFrameCount(scaledInputFrameLength.rounded(.up))
        guard let conversionBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: frameCapacity
        ) else {
            throw SpeechSessionError.conversionBufferCreationFailed
        }

        var nsError: NSError?

        final class BufferState: @unchecked Sendable {
            var processed = false
        }
        let bufferState = BufferState()

        let status = converter.convert(to: conversionBuffer, error: &nsError) { _, inputStatusPointer in
            // This closure can be called multiple times, but it only offers a single buffer.
            defer { bufferState.processed = true }
            inputStatusPointer.pointee = bufferState.processed ? .noDataNow : .haveData
            return bufferState.processed ? nil : buffer
        }

        guard status != .error else {
            throw SpeechSessionError.audioConversionFailed(nsError)
        }

        return conversionBuffer
    }
}
