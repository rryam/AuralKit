import Testing
import AVFoundation
import Speech
@testable import AuralKit

@Suite("File transcription")
struct FileTranscriptionTests {

    @Test("transcribe throws audioFileNotFound for missing file")
    @MainActor
    func transcribeMissingFileThrowsNotFound() async throws {
        let session = SpeechSession()
        let missingURL = URL(fileURLWithPath: "/tmp/not-real-")

        await #expect(throws: SpeechSessionError.self) {
            _ = try await session.transcribe(audioFile: missingURL)
        }
    }

    @Test("transcribe rejects audio exceeding maximum duration")
    @MainActor
    func transcribeRejectsAudioExceedingMaximumDuration() async throws {
        let tempURL = try createSilenceAudioFile(duration: 2.0)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let session = SpeechSession()
        let options = FileTranscriptionOptions(maxDuration: 1.0)

        await #expect(throws: SpeechSessionError.self) {
            _ = try await session.transcribe(audioFile: tempURL, options: options)
        }
    }

#if swift(>=6.4)
    @Test("Stopping a file analyzer before it receives input closes the session")
    @MainActor
    func stopBeforeAnalyzerInputClosesSession() async throws {
        let session = SpeechSession()
        let (results, continuation) = AsyncThrowingStream<SpeechTranscriber.Result, Error>.makeStream()
        session.analyzer = SpeechAnalyzer(modules: [])
        session.continuation = .speech(continuation)
        session.streamingMode = .filePlayback
        session.setStatus(.preparing)

        try await awaitResult(timeout: 3) { await session.stopTranscribing() }

        var iterator = results.makeAsyncIterator()
        let nextResult = try await iterator.next()
        #expect(nextResult == nil)
        #expect(session.status == .idle)
    }

    @available(iOS 27.0, macOS 27.0, *)
    @Test("Media transcription rejects an unknown audio track without falling back")
    @MainActor
    func mediaTranscriptionRejectsUnknownTrack() async throws {
        let url = try createSilenceAudioFile(duration: 2.0)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try #require(tracks.first)
        let session = SpeechSession()

        let stream = session.streamTranscription(fromMediaFile: url, audioTrackID: track.trackID + 1)
        do {
            for try await _ in stream { }
            Issue.record("Expected the unknown track to be rejected")
        } catch SpeechSessionError.audioFileUnsupportedFormat(let reason) {
            #expect(reason.contains("\(track.trackID + 1)"))
        }
    }
#endif

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
    func transcribeNonFileURLThrowsInvalidURL() async throws {
        let session = SpeechSession()
        let httpURL = URL(string: "https://example.com/audio.wav")!

        await #expect(throws: SpeechSessionError.self) {
            _ = try await session.transcribe(audioFile: httpURL)
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

        await #expect(throws: SpeechSessionError.self) {
            _ = try await session.transcribe(audioFile: tempURL, options: restrictedOptions)
        }
    }
}
