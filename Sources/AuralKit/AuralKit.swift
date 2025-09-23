import Foundation

// MARK: - AuralKit

@available(iOS 26.0, macOS 26.0, *)
public final class AuralKit {

    // MARK: - Properties

    private let permissionsManager = PermissionsManager()
#if os(iOS)
    private let audioSessionManager = AudioSessionManager()
#endif
    private let audioStreamer = AudioStreamer()
    private let transcriberManager = SpeechTranscriberManager()
    private let converter = BufferConverter()

    private var recognizerTask: Task<(), Error>?

    private let locale: Locale

    // MARK: - Init

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    // MARK: - Public API

    /// Start transcribing
    public func startTranscribing() -> AsyncThrowingStream<AttributedString, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Request permissions
                    guard await permissionsManager.isAuthorized() else {
                        throw NSError(domain: "AuralKit", code: -10, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied"])
                    }

#if os(iOS)
                    try audioSessionManager.setUpAudioSession()
#endif

                    let transcriber = try await transcriberManager.setUpTranscriber(locale: locale)

                    // Set up recognition task
                    recognizerTask = Task {
                        do {
                            for try await result in transcriber.results {
                                continuation.yield(result.text)
                            }
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }

                    // Start audio stream
                    try audioStreamer.startStreaming(with: transcriberManager, converter: converter)

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Stop transcribing
    public func stopTranscribing() async {
        audioStreamer.stop()
        await transcriberManager.stop()
        recognizerTask?.cancel()
        recognizerTask = nil
    }
}
