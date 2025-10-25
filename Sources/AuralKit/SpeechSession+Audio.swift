import Foundation
@preconcurrency import AVFoundation

private final class WeakSpeechSessionBox: @unchecked Sendable {
    weak var value: SpeechSession?

    init(_ value: SpeechSession) {
        self.value = value
    }
}

private func currentQueueLabel() -> String {
    String(cString: __dispatch_queue_get_label(nil))
}

private func makeAudioTapHandler(for session: SpeechSession) -> AVAudioNodeTapBlock {
    let weakSession = WeakSpeechSessionBox(session)

    return { buffer, _ in
        print("[AudioTap] invoked on queue: \(currentQueueLabel()), main thread: \(Thread.isMainThread)")
        guard let bufferCopy = buffer.copy() as? AVAudioPCMBuffer else {
            print("[AudioTap] failed to copy buffer")
            return
        }

        Task { @MainActor in
            guard let session = weakSession.value else {
                print("[AudioTap] session deallocated before processing")
                return
            }

            do {
                try session.processAudioBuffer(bufferCopy)
            } catch {
                if SpeechSession.shouldLog(.error) {
                    SpeechSession.logger.error("Audio processing error: \(error.localizedDescription, privacy: .public)")
                }
                print("[AudioTap] audio processing error: \(error)")
            }
        }
    }
}

@MainActor
extension SpeechSession {

    private static let microphoneTapBufferSize: AVAudioFrameCount = 2048

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
        print("[AudioTap] startAudioStreaming entered; queue: \(currentQueueLabel()), main thread: \(Thread.isMainThread)")
        if Self.shouldLog(.debug) {
            Self.logger.debug("Installing audio tap with buffer size \(Self.microphoneTapBufferSize, privacy: .public) frames")
        }

        audioEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: Self.microphoneTapBufferSize,
            format: inputFormat,
            block: makeAudioTapHandler(for: self)
        )
        print("[AudioTap] tap installed; queue: \(currentQueueLabel()), main thread: \(Thread.isMainThread)")

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

            let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
            let previousPortType = previousRoute?.inputs.first?.portType

            Task { [weak self] in
                guard let self else { return }
                await self.handleRouteChange(reason, previousPortType: previousPortType)
            }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt

            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.handleAudioSessionInterruption(typeValue: typeValue, optionsValue: optionsValue)
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
                Self.logger.error(
                    "Failed to reset audio engine after route change: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        publishCurrentAudioInputInfo()
    }

    func handleAudioSessionInterruption(typeValue: UInt?, optionsValue: UInt?) async {
        guard let typeValue,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            handleInterruptionBegan()
        case .ended:
            let value = optionsValue ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: value)
            await handleInterruptionEnded(options: options)
        @unknown default:
            break
        }
    }

    private func handleInterruptionBegan() {
        guard streamingMode == .liveMicrophone else {
            shouldResumeAfterInterruption = false
            return
        }

        shouldResumeAfterInterruption = status == .transcribing && isAudioStreaming
        if shouldResumeAfterInterruption {
            if Self.shouldLog(.notice) {
                Self.logger.notice("Audio session interruption began; pausing stream")
            }
            stopAudioStreaming()
            setStatus(.paused)
        }

        isAudioSessionActive = false
    }

    private func handleInterruptionEnded(options: AVAudioSession.InterruptionOptions) async {
        guard shouldResumeAfterInterruption else { return }
        shouldResumeAfterInterruption = false

        guard options.contains(.shouldResume) else {
            if Self.shouldLog(.notice) {
                Self.logger.notice("Audio session interruption ended without resume option; cleaning up session")
            }
            prepareForStop()
            await cleanup(cancelRecognizer: true)
            await finishStream(error: nil)
            return
        }

        do {
            try await setupAudioSession()
            try startAudioStreaming()
            setStatus(.transcribing)
            if Self.shouldLog(.notice) {
                Self.logger.notice("Audio session resumed after interruption")
            }
        } catch {
            if Self.shouldLog(.error) {
                let description = error.localizedDescription
                Self.logger.error("Failed to resume after interruption: \(description, privacy: .public)")
            }
            prepareForStop()
            await cleanup(cancelRecognizer: true)
            await finishStream(error: error)
        }
    }
#elseif os(macOS)
    func handleEngineConfigurationChange() async {
        do {
            try await reset()
        } catch {
            if Self.shouldLog(.error) {
                let desc = error.localizedDescription
                Self.logger.error(
                    "Failed to reset audio engine after configuration change: \(desc, privacy: .public)"
                )
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
            broadcastAudioInputInfo(AudioInputInfo(from: input))
        } else {
            if Self.shouldLog(.debug) {
                Self.logger.debug("No active audio input detected")
            }
            broadcastAudioInputInfo(nil)
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
            broadcastAudioInputInfo(info)
        } catch {
            if Self.shouldLog(.error) {
                Self.logger.error(
                    "Failed to obtain audio input details: \(error.localizedDescription, privacy: .public)"
                )
            }
            broadcastAudioInputInfo(nil)
        }
#endif
    }
#endif

#if os(iOS) || os(macOS)
    func broadcastAudioInputInfo(_ info: AudioInputInfo?) {
        for continuation in audioInputContinuations.values {
            continuation.yield(info)
        }
    }

    func finishAudioInputStreams() {
        for continuation in audioInputContinuations.values {
            continuation.finish()
        }
        audioInputContinuations.removeAll()
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
