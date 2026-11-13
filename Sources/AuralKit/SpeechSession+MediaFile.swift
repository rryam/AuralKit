#if swift(>=6.4)
import AVFoundation
import CoreMedia
import Foundation
import Speech

@available(iOS 27.0, macOS 27.0, *)
public extension SpeechSession {
    /// Stream transcription results from one audio track of a local media file, such as a movie.
    ///
    /// - Parameters:
    ///   - mediaFile: A local file URL in one of `options.allowedDirectories`.
    ///   - audioTrackID: An ID from the file's audio tracks. Pass `nil` to use its first audio track.
    ///   - options: Contextual strings, allowed directories, and the maximum selected track duration.
    /// - Returns: An async throwing stream of transcription results on the media timeline.
    func streamTranscription(
        fromMediaFile mediaFile: URL,
        audioTrackID: CMPersistentTrackID? = nil,
        options: FileTranscriptionOptions = .init()
    ) -> AsyncThrowingStream<SpeechTranscriber.Result, Error> {
        startFileTranscription { session, continuation, generation in
            await session.startMediaFilePipeline(
                mediaFile, audioTrackID: audioTrackID, options: options,
                continuation: continuation, generation: generation
            )
        }
    }
}

@available(iOS 27.0, macOS 27.0, *)
private extension SpeechSession {
    func startMediaFilePipeline(
        _ mediaFile: URL,
        audioTrackID: CMPersistentTrackID?,
        options: FileTranscriptionOptions,
        continuation: FileResultContinuation,
        generation: Int
    ) async {
        do {
            try Task.checkCancellation()
            let url = try sanitizeAudioFileURL(mediaFile, allowedDirectories: options.allowedDirectories)
            let asset = AVURLAsset(url: url)
            let track = try await loadAudioTrack(from: asset, id: audioTrackID, maxDuration: options.maxDuration)
            try Task.checkCancellation()
            try await ensureSpeechRecognitionAuthorization(context: "for media file transcription")
            try Task.checkCancellation()
            try await setUpFilePipeline(
                with: continuation,
                contextualStrings: options.contextualStrings,
                startAnalyzerImmediately: false,
                generation: generation
            )
            try Task.checkCancellation()
            guard let analyzer, let activeModules else {
                throw SpeechSessionError.recognitionStreamSetupFailed
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: activeModules) else {
                throw SpeechSessionError.invalidAudioDataType
            }
            try Task.checkCancellation()
            let provider = AssetInputSequenceProvider(asset: asset, track: track, analyzerFormat: format)
            let inputs = provider.analyzerInputs
            startFileIngestion(generation: generation) { session in
                try await session.prepareAnalyzerForStartIfNeeded(in: format)
                try Task.checkCancellation()
                session.startSpeechDetectorMonitoringIfNeeded()

                let endTime = try await analyzer.analyzeSequence(inputs)
                try Task.checkCancellation()
                if let endTime {
                    try await analyzer.finalizeAndFinish(through: endTime)
                } else {
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                }
            }
        } catch {
            await finishFailedPipelineSetup(error, generation: generation)
        }
    }

    func loadAudioTrack(
        from asset: AVAsset,
        id: CMPersistentTrackID?,
        maxDuration: TimeInterval?
    ) async throws -> AVAssetTrack {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first(where: { id == nil || $0.trackID == id }) else {
            let reason = id.map { "Audio track ID \($0) was not found" } ?? "the media file has no audio tracks"
            throw SpeechSessionError.audioFileUnsupportedFormat(reason)
        }
        let duration = try await track.load(.timeRange).duration.seconds
        guard duration.isFinite, duration > 0 else {
            throw SpeechSessionError.audioFileUnsupportedFormat("the audio track has no finite, positive duration")
        }
        if let maxDuration, duration > maxDuration {
            throw SpeechSessionError.audioFileTooLong(maximum: maxDuration, actual: duration)
        }
        return track
    }
}
#endif
