import Foundation
@preconcurrency import AVFoundation
import Speech

@MainActor
extension SpeechSession {

    private static let microphoneTapBufferSize: AVAudioFrameCount = 2048

    // MARK: - Audio Streaming

    func startAudioStreaming() throws {
        guard !isAudioStreaming else {
            throw SpeechSessionError.recognitionStreamSetupFailed
        }

#if swift(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *), startPreparedNativeCaptureStreaming() {
            return
        }
#endif

        if Self.shouldLog(.debug) {
            Self.logger.debug("Starting audio streaming")
        }

        guard let inputBuilder, let analyzerFormat else {
            throw SpeechSessionError.invalidAudioDataType
        }

        audioEngine.inputNode.removeTap(onBus: 0)

        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)

        if Self.shouldLog(.debug) {
            Self.logger.debug(
                "Installing audio tap with buffer size \(Self.microphoneTapBufferSize, privacy: .public) frames"
            )
        }

        audioEngine.inputNode.installTap(
            onBus: 0,
            bufferSize: Self.microphoneTapBufferSize,
            format: inputFormat,
            block: makeAudioTapHandler(inputBuilder: inputBuilder, analyzerFormat: analyzerFormat)
        )

        audioEngine.prepare()
        try audioEngine.start()
        isAudioStreaming = true
        if Self.shouldLog(.debug) {
            Self.logger.debug("Audio streaming started")
        }
    }

    func stopAudioStreaming() {
        guard isAudioStreaming else { return }

#if swift(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *), stopPreparedNativeCaptureStreaming() {
            return
        }
#endif

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
            guard let self else { return }
            Task {
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
            guard let self else { return }
            Task { @MainActor in
                await self.handleAudioSessionInterruption(typeValue: typeValue, optionsValue: optionsValue)
            }
        }
#elseif os(macOS)
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.handleEngineConfigurationChange()
            }
        }
#endif
    }

    /// Build a tap block that converts and forwards buffers synchronously on the tap thread.
    ///
    /// Converting inline (rather than hopping through per-buffer tasks) guarantees analyzer
    /// input arrives in capture order and keeps working across cleanup: yields into a finished
    /// stream are simply dropped. A fresh converter is captured per installation so a route or
    /// device change (which reinstalls the tap with a new format) never reuses a stale converter.
    private func makeAudioTapHandler(
        inputBuilder: AsyncStream<AnalyzerInput>.Continuation,
        analyzerFormat: AVAudioFormat
    ) -> AVAudioNodeTapBlock {
        let converter = BufferConverter()
        return { buffer, _ in
            do {
                let converted = try converter.convertBuffer(buffer, to: analyzerFormat)
                let input: AVAudioPCMBuffer
                if converted === buffer {
                    // Passthrough: the engine reuses the tap buffer, so hand the analyzer a copy.
                    guard let bufferCopy = buffer.copy() as? AVAudioPCMBuffer else {
                        Task { @MainActor in
                            if Self.shouldLog(.error) {
                                Self.logger.error("Failed to copy audio buffer for processing.")
                            }
                        }
                        return
                    }
                    input = bufferCopy
                } else {
                    input = converted
                }
                inputBuilder.yield(AnalyzerInput(buffer: input))
            } catch {
                let description = error.localizedDescription
                Task { @MainActor in
                    if Self.shouldLog(.error) {
                        Self.logger.error(
                            "Audio processing error: \(description, privacy: .public)"
                        )
                    }
                }
            }
        }
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
        let generation = sessionGeneration

        guard options.contains(.shouldResume) else {
            if Self.shouldLog(.notice) {
                Self.logger.notice("Audio session interruption ended without resume option; cleaning up session")
            }
            prepareForStop()
            await cleanup(cancelRecognizer: true, generation: generation)
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
            await cleanup(cancelRecognizer: true, generation: generation)
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
        let wasUsingNativeCapture = nativeCaptureSession != nil

        if wasUsingNativeCapture {
            guard wasStreaming else { return }
            guard try restartNativeCaptureStreamingIfAvailable() else {
                throw SpeechSessionError.recognitionStreamSetupFailed
            }

            if Self.shouldLog(.debug) {
                Self.logger.debug("Native capture session reset complete")
            }
            return
        }

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
