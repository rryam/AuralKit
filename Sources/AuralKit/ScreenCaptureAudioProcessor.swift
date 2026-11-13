import AVFoundation
import CoreMedia
import Foundation
import Speech

/// Serializes audio conversion and admits callbacks only from the currently running stream.
final class ScreenCaptureAudioProcessor: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.auralkit.screencapture.audio", qos: .userInitiated)
    private let conversion: any ScreenCaptureAudioConversion
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let onError: @Sendable (Error) -> Void
    // Accessed only on queue, including during start and stop.
    private var activeStream: ObjectIdentifier?

    init(
        targetFormat: AVAudioFormat,
        useNativeConversion: Bool,
        input: AsyncStream<AnalyzerInput>.Continuation,
        onError: @escaping @Sendable (Error) -> Void
    ) {
#if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *), useNativeConversion {
            conversion = NativeScreenCaptureAudioConversion(targetFormat: targetFormat)
        } else {
            conversion = LegacyScreenCaptureAudioConversion(targetFormat: targetFormat)
        }
#else
        conversion = LegacyScreenCaptureAudioConversion(targetFormat: targetFormat)
#endif
        self.input = input
        self.onError = onError
    }

    func start(_ stream: ObjectIdentifier) {
        queue.sync { activeStream = stream }
    }

    func drain(_ stream: ObjectIdentifier) -> Error? {
        queue.sync {
            guard activeStream == stream else { return nil }
            activeStream = nil
            do {
                try yield(conversion.flush())
                return nil
            } catch {
                return error
            }
        }
    }

    func discard(_ stream: ObjectIdentifier? = nil) {
        queue.sync {
            guard stream == nil || activeStream == stream else { return }
            activeStream = nil
            conversion.discard()
        }
    }

    func receive(_ sample: CMSampleBuffer, from stream: ObjectIdentifier) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard activeStream == stream, sample.isValid, sample.numSamples > 0,
              sample.dataReadiness == .ready,
              let description = sample.formatDescription?.audioStreamBasicDescription,
              description.mFormatID == kAudioFormatLinearPCM else { return }
        var sourceDescription = description
        guard let format = AVAudioFormat(streamDescription: &sourceDescription) else { return }
        do {
            try yield(conversion.convert(sample, format: format))
        } catch {
            activeStream = nil
            conversion.discard()
            onError(error)
        }
    }

    private func yield(_ inputs: [AnalyzerInput]) {
        for buffer in inputs { input.yield(buffer) }
    }
}

private protocol ScreenCaptureAudioConversion {
    func convert(_ sample: CMSampleBuffer, format: AVAudioFormat) throws -> [AnalyzerInput]
    func flush() throws -> [AnalyzerInput]
    func discard()
}

private func copyPCMBuffer(_ sample: CMSampleBuffer, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
    let frameCount = AVAudioFrameCount(sample.numSamples)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw SpeechSessionError.conversionBufferCreationFailed
    }
    buffer.frameLength = frameCount
    do {
        try sample.copyPCMData(fromRange: 0..<sample.numSamples, into: buffer.mutableAudioBufferList)
    } catch {
        throw SpeechSessionError.screenCaptureFailed(error)
    }
    return buffer
}

private struct LegacyScreenCaptureAudioConversion: ScreenCaptureAudioConversion {
    let targetFormat: AVAudioFormat
    private let converter = BufferConverter()

    func convert(_ sample: CMSampleBuffer, format: AVAudioFormat) throws -> [AnalyzerInput] {
        let source = try copyPCMBuffer(sample, format: format)
        let converted = try converter.convertBuffer(source, to: targetFormat)
        return [AnalyzerInput(buffer: converted)]
    }

    func flush() -> [AnalyzerInput] { [] }
    func discard() {}
}

#if compiler(>=6.4)
@available(iOS 27.0, macOS 27.0, *)
private final class NativeScreenCaptureAudioConversion: ScreenCaptureAudioConversion {
    private let targetFormat: AVAudioFormat
    private var converter: AnalyzerInputConverter?
    private var converterSourceFormat: AVAudioFormat?
    private var nextFrame: AVAudioFramePosition = 0

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    func convert(_ sample: CMSampleBuffer, format: AVAudioFormat) throws -> [AnalyzerInput] {
        var inputs: [AnalyzerInput] = []
        if format == targetFormat, sample.dataBuffer != nil {
            inputs = try flush()
            // Keep the existing contiguous transcript clock across pauses and source changes.
            // Copy the timing metadata while retaining the original audio data.
            let rate = CMTimeScale(targetFormat.sampleRate)
            let timing = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: rate),
                presentationTimeStamp: CMTime(value: nextFrame, timescale: rate),
                decodeTimeStamp: .invalid
            )
            let frameCount = AVAudioFramePosition(sample.numSamples)
            // The copied sample buffer and its retained data remain read-only after handoff.
            nonisolated(unsafe) let retimed = try CMSampleBuffer(copying: sample, withNewTiming: [timing])
            let input = AnalyzerInput(buffer: CMReadySampleBuffer(unsafeWithDataBuffer: retimed))
            nextFrame += frameCount
            inputs.append(input)
            return inputs
        }

        let source = try copyPCMBuffer(sample, format: format)
        if converterSourceFormat != format {
            inputs = try flush()
        }
        let time: AVAudioTime?
        let activeConverter: AnalyzerInputConverter
        if let converter {
            activeConverter = converter
            time = nil
        } else {
            activeConverter = AnalyzerInputConverter(analyzerFormat: targetFormat)
            converter = activeConverter
            converterSourceFormat = format
            time = AVAudioTime(sampleTime: nextFrame, atRate: targetFormat.sampleRate)
        }
        let converted = try activeConverter.convert(source, at: time)
        advanceClock(with: converted)
        inputs += converted
        return inputs
    }

    func flush() throws -> [AnalyzerInput] {
        guard let converter else { return [] }
        discard()
        let remaining = try converter.flush()
        advanceClock(with: remaining)
        return remaining
    }

    func discard() {
        converter = nil
        converterSourceFormat = nil
    }

    private func advanceClock(with inputs: [AnalyzerInput]) {
        for input in inputs {
            nextFrame += input.bufferDuration.convertScale(
                CMTimeScale(targetFormat.sampleRate), method: .roundHalfAwayFromZero
            ).value
        }
    }
}
#endif
