import Testing
import AVFoundation
@testable import AuralKit

@Suite("File transcription")
struct FileTranscriptionTests {

    @Test("transcribe throws audioFileNotFound for missing file")
    @MainActor
    func transcribeMissingFileThrowsNotFound() async {
        let session = SpeechSession()
        let missingURL = URL(fileURLWithPath: "/tmp/not-real-")

        do {
            _ = try await session.transcribe(audioFile: missingURL)
            Issue.record("Expected audioFileNotFound error")
        } catch let error as SpeechSessionError {
            guard case let .audioFileNotFound(url) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(url == missingURL)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("transcribe rejects audio exceeding maximum duration")
    @MainActor
    func transcribeRejectsAudioExceedingMaximumDuration() async throws {
        let tempURL = try createSilenceAudioFile(duration: 2.0)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let session = SpeechSession()
        let options = FileTranscriptionOptions(maxDuration: 1.0)

        do {
            _ = try await session.transcribe(audioFile: tempURL, options: options)
            Issue.record("Expected audioFileTooLong error")
        } catch let error as SpeechSessionError {
            guard case let .audioFileTooLong(maximum, actual) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect((maximum - 1.0).magnitude < 0.01)
            #expect(actual > maximum)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func createSilenceAudioFile(duration: TimeInterval, sampleRate: Double = 44_100) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw NSError(
                domain: "FileTranscriptionTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"]
            )
        }

        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(
                domain: "FileTranscriptionTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"]
            )
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

    @Test("transcribe throws audioFileInvalidURL for non-file URL")
    @MainActor
    func transcribeNonFileURLThrowsInvalidURL() async {
        let session = SpeechSession()
        let httpURL = URL(string: "https://example.com/audio.wav")!

        do {
            _ = try await session.transcribe(audioFile: httpURL)
            Issue.record("Expected audioFileInvalidURL error")
        } catch let error as SpeechSessionError {
            guard case let .audioFileInvalidURL(url) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(url == httpURL)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("transcribe throws audioFileOutsideAllowedDirectories for restricted path")
    @MainActor
    func transcribeOutsideAllowedDirectoriesThrows() async throws {
        let tempURL = try createSilenceAudioFile(duration: 0.5)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let session = SpeechSession()
        let restrictedOptions = FileTranscriptionOptions(
            allowedDirectories: [URL(fileURLWithPath: "/nonexistent/path")]
        )

        do {
            _ = try await session.transcribe(audioFile: tempURL, options: restrictedOptions)
            Issue.record("Expected audioFileOutsideAllowedDirectories error")
        } catch let error as SpeechSessionError {
            guard case .audioFileOutsideAllowedDirectories = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
