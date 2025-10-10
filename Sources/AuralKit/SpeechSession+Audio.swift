import Foundation
import AVFoundation

@MainActor
extension SpeechSession {

    // MARK: - Audio Streaming

    func startAudioStreaming() throws {
        guard !isAudioStreaming else {
            throw SpeechSessionError.recognitionStreamSetupFailed
        }

        if Self.shouldLog(.debug) {
            Self.logger.debug("Starting audio streaming")
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
                    if Self.shouldLog(.error) {
                        Self.logger.error("Audio processing error: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isAudioStreaming = true
        if Self.shouldLog(.debug) {
            Self.logger.debug("Audio streaming started")
        }
    }

    func stopAudioStreaming() {
        guard isAudioStreaming else { return }
        if Self.shouldLog(.debug) {
            Self.logger.debug("Stopping audio streaming")
        }
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
            if Self.shouldLog(.error) {
                Self.logger.error("Failed to reset audio engine after route change: \(error.localizedDescription, privacy: .public)")
            }
        }

        publishCurrentAudioInputInfo()
    }
#elseif os(macOS)
    func handleEngineConfigurationChange() async {
        do {
            try await reset()
        } catch {
            if Self.shouldLog(.error) {
                Self.logger.error("Failed to reset audio engine after configuration change: \(error.localizedDescription, privacy: .public)")
            }
        }

        publishCurrentAudioInputInfo()
    }
#endif

#if os(iOS) || os(macOS)
    func publishCurrentAudioInputInfo() {
#if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        if let input = audioSession.currentRoute.inputs.first {
            if Self.shouldLog(.info) {
                Self.logger.info("Publishing audio input info for port: \(input.portName, privacy: .public)")
            }
            audioInputConfigurationContinuation?.yield(AudioInputInfo(from: input))
        } else {
            if Self.shouldLog(.debug) {
                Self.logger.debug("No active audio input detected")
            }
            audioInputConfigurationContinuation?.yield(nil)
        }
#elseif os(macOS)
        do {
            let info = try AudioInputInfo.current()
            if let info {
                if Self.shouldLog(.info) {
                    Self.logger.info("Publishing audio input info for port: \(info.portName, privacy: .public)")
                }
            } else {
                if Self.shouldLog(.debug) {
                    Self.logger.debug("No active audio input detected")
                }
            }
            audioInputConfigurationContinuation?.yield(info)
        } catch {
            if Self.shouldLog(.error) {
                Self.logger.error("Failed to obtain audio input details: \(error.localizedDescription, privacy: .public)")
            }
            audioInputConfigurationContinuation?.yield(nil)
        }
#endif
    }
#endif

    func reset() async throws {
        if Self.shouldLog(.debug) {
            Self.logger.debug("Resetting audio engine")
        }
        let wasStreaming = isAudioStreaming

        if wasStreaming {
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        audioEngine.stop()
        audioEngine.reset()
        isAudioStreaming = false

        guard wasStreaming else { return }
        try startAudioStreaming()
        if Self.shouldLog(.debug) {
            Self.logger.debug("Audio engine reset complete")
        }
    }
}
