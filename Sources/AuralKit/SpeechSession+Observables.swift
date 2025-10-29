import Foundation

extension SpeechSession {
    /// Async stream that emits lifecycle status updates, beginning with the current status.
    public var statusStream: AsyncStream<Status> {
        AsyncStream { [weak self] continuation in
            let id = UUID()
            Task { @MainActor [weak self] in
                guard let self else { return }
                continuation.yield(self.status)
                self.statusContinuations[id] = continuation
            }

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.statusContinuations.removeValue(forKey: id)
                }
            }
        }
    }

#if os(iOS) || os(macOS)
    /// Stream that delivers `AudioInputInfo` updates whenever the active audio input changes.
    public var audioInputConfigurationStream: AsyncStream<AudioInputInfo?> {
        AsyncStream { [weak self] continuation in
            let id = UUID()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.audioInputContinuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.audioInputContinuations.removeValue(forKey: id)
                }
            }
        }
    }
#endif

    /// Progress of the ongoing model download, if any.
    public var modelDownloadProgress: Progress? {
        get async {
            await modelManager.currentDownloadProgress
        }
    }

    /// Returns `true` when voice activation has been configured for the session.
    public var isVoiceActivationEnabled: Bool {
        voiceActivationConfiguration != nil
    }
}
