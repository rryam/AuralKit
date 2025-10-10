import XCTest
import AVFoundation
@testable import AuralKit

final class FileTranscriptionTests: XCTestCase {
    @MainActor
    func testTranscribeMissingFileThrowsNotFound() async {
        let session = SpeechSession()
        let missingURL = URL(fileURLWithPath: "/tmp/not-real-")

        do {
            _ = try await session.transcribe(audioFile: missingURL)
            XCTFail("Expected audioFileNotFound error")
        } catch let error as SpeechSessionError {
            guard case let .audioFileNotFound(url) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(url, missingURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testTranscribeRejectsAudioExceedingMaximumDuration() async throws {
        let tempURL = try createSilenceAudioFile(duration: 2.0)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let session = SpeechSession()
        let options = FileTranscriptionOptions(maxDuration: 1.0)

        do {
            _ = try await session.transcribe(audioFile: tempURL, options: options)
            XCTFail("Expected audioFileTooLong error")
        } catch let error as SpeechSessionError {
            guard case let .audioFileTooLong(maximum, actual) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(maximum, 1.0, accuracy: 0.01)
            XCTAssertGreaterThan(actual, maximum)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func createSilenceAudioFile(duration: TimeInterval, sampleRate: Double = 44_100) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw NSError(domain: "FileTranscriptionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"])
        }

        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "FileTranscriptionTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }

        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                channelData[channel].initialize(repeating: 0, count: Int(buffer.frameLength))
            }
        }

        let audioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try audioFile.write(from: buffer)

        return tempURL
    }
}
