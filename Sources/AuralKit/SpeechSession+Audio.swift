import Foundation
import AVFoundation

@MainActor
extension SpeechSession {

    // MARK: - Audio Streaming

    func startAudioStreaming() throws {
        guard !isAudioStreaming else {
            throw SpeechSessionError.recognitionStreamSetupFailed
        }

        audioEngine.inputNode.removeTap(onBus: 0)

        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)

        audioEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat
        ) { [weak self] buffer, _ in
            guard let self,
                  let bufferCopy = buffer.copy() as? AVAudioPCMBuffer else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try self.processAudioBuffer(bufferCopy)
                } catch {
                    Self.log("Audio processing error: \(error.localizedDescription)", level: .error)
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isAudioStreaming = true
    }

    func stopAudioStreaming() {
        guard isAudioStreaming else { return }
        audioEngine.stop()
        isAudioStreaming = false
    }

    func setupAudioConfigurationObservers() {
#if os(iOS)
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
            }

            let previousPortType = (userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription)?
                .inputs.first?.portType

            Task { [weak self] in
                guard let self else { return }
                await self.handleRouteChange(reason, previousPortType: previousPortType)
            }
        }
#elseif os(macOS)
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                guard let self else { return }
                await self.handleEngineConfigurationChange()
            }
        }
#endif
    }

#if os(iOS)
    func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason, previousPortType: AVAudioSession.Port?) async {
        let session = AVAudioSession.sharedInstance()
        let currentPortType = session.currentRoute.inputs.first?.portType

        guard previousPortType != currentPortType else {
            return
        }

        do {
            try await reset()
        } catch {
            Self.log("Failed to reset audio engine after route change: \(error.localizedDescription)", level: .error)
        }

        publishCurrentAudioInputInfo()
    }
#elseif os(macOS)
    func handleEngineConfigurationChange() async {
        do {
            try await reset()
        } catch {
            Self.log("Failed to reset audio engine after configuration change: \(error.localizedDescription)", level: .error)
        }

        publishCurrentAudioInputInfo()
    }
#endif

#if os(iOS) || os(macOS)
    func publishCurrentAudioInputInfo() {
#if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        if let input = audioSession.currentRoute.inputs.first {
            audioInputConfigurationContinuation?.yield(AudioInputInfo(from: input))
        } else {
            audioInputConfigurationContinuation?.yield(nil)
        }
#elseif os(macOS)
        do {
            let info = try AudioInputInfo.current()
            audioInputConfigurationContinuation?.yield(info)
        } catch {
            Self.log("Failed to obtain audio input details: \(error.localizedDescription)", level: .error)
            audioInputConfigurationContinuation?.yield(nil)
        }
#endif
    }
#endif

    func reset() async throws {
        let wasStreaming = isAudioStreaming

        if wasStreaming {
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        audioEngine.stop()
        audioEngine.reset()
        isAudioStreaming = false

        guard wasStreaming else { return }
        try startAudioStreaming()
    }
}
