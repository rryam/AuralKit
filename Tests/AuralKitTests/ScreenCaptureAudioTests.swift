#if compiler(>=6.4)
import AVFoundation
import CoreMedia
import Speech
import Testing
@testable import AuralKit

struct ScreenCaptureAudioTests {
    @Test(arguments: [true, false])
    func conversionKeepsOneTimelineAcrossCaptureStreams(drain: Bool) async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else { return }
        let target = try #require(AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true
        ))
        let source = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: true
        ))
        let (inputs, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let processor = ScreenCaptureAudioProcessor(
            targetFormat: target, useNativeConversion: true, input: continuation
        ) {
            Issue.record("Screen audio failed: \($0)")
        }
        let firstStream = NSObject()
        let secondStream = NSObject()
        let first = ObjectIdentifier(firstStream)
        let second = ObjectIdentifier(secondStream)
        let convertible = try makeSample(format: source, frames: 3072, timestamp: 123)
        let compatible = try makeSample(format: target, frames: 160, timestamp: 1)

        processor.start(first)
        processor.queue.sync { processor.receive(convertible, from: first) }
        processor.stop(first, drain: drain)
        // Restart the same native stream, as when resuming from pause.
        processor.queue.sync { processor.receive(compatible, from: first) }
        processor.start(first)
        processor.queue.sync { processor.receive(compatible, from: first) }
        processor.stop(first)
        processor.start(second)
        processor.queue.sync {
            processor.receive(compatible, from: first)
            processor.receive(compatible, from: second)
        }
        processor.stop(second)
        processor.queue.sync { processor.receive(compatible, from: second) }
        continuation.finish()

        var nextTime = CMTime.zero
        var durations: [CMTime] = []
        for await input in inputs {
            #expect(input.bufferFormat == target)
            #expect(input.bufferStartTime == nextTime)
            nextTime = CMTimeAdd(nextTime, input.bufferDuration)
            durations.append(input.bufferDuration)
        }
        let directDuration = CMTime(value: 160, timescale: 16_000)
        #expect(durations.suffix(2).elementsEqual([directDuration, directDuration]))
        if drain {
            #expect(nextTime == CMTime(value: 1344, timescale: 16_000))
        } else {
            #expect(nextTime < CMTime(value: 1344, timescale: 16_000))
        }
        withExtendedLifetime((firstStream, secondStream)) {}
    }

    private func makeSample(format: AVAudioFormat, frames: Int, timestamp: Int64) throws -> CMSampleBuffer {
        let byteCount = frames * Int(format.streamDescription.pointee.mBytesPerFrame)
        var data: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &data
        )
        #expect(status == noErr)
        let block = try #require(data)
        #expect(CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
            == noErr)
        return try CMSampleBuffer(
            dataBuffer: block, formatDescription: format.formatDescription, numSamples: frames,
            sampleTimings: [CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: CMTimeScale(format.sampleRate)),
                presentationTimeStamp: CMTime(value: timestamp, timescale: 1),
                decodeTimeStamp: .invalid
            )],
            sampleSizes: [Int(format.streamDescription.pointee.mBytesPerFrame)]
        )
    }
}
#endif
