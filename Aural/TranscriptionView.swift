import SwiftUI
import AuralKit
import Speech

/// Minimal example showing how easy SpeechSession is to use
struct TranscriptionView: View {
    @State private var presetChoice: DemoTranscriberPreset = .manual
    @State private var session = SpeechSession(preset: DemoTranscriberPreset.manual.preset)
    @State private var finalText: AttributedString = ""
    @State private var partialText: AttributedString = ""
#if os(iOS)
    @State private var micInput: AudioInputInfo?
#endif
    @State private var status: SpeechSession.Status = .idle
    @State private var error: String?
    @State private var transcriptionTask: Task<Void, Never>?
    @State private var enableVAD: Bool = false
    @State private var vadSensitivity: SpeechDetector.SensitivityLevel = .medium
    @State private var isSpeechDetected: Bool = true
    @State private var logLevel: SpeechSession.LogLevel = SpeechSession.logging
    @State private var vadConfigurationToken = UUID()

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                TranscriptionSettingsView(
                    presetChoice: $presetChoice,
                    enableVAD: $enableVAD,
                    vadSensitivity: $vadSensitivity,
                    isSpeechDetected: $isSpeechDetected,
                    logLevel: $logLevel
                )

                TranscriptionTextView(
                    finalText: finalText,
                    partialText: partialText
                )

                Spacer()

                TranscriptionControlsView(
                    status: status,
                    error: error,
                    showStopButton: showStopButton,
                    buttonColor: buttonColor,
                    buttonIcon: buttonIcon,
                    statusMessage: statusMessage,
                    onPrimaryAction: handlePrimaryAction,
                    onStopAction: handleStopAction
                )
            }
            .frame(maxWidth: .infinity)
            .background(TopGradientView())
            .navigationTitle("Aural")
#if os(iOS)
            .toolbar {
                if !String(finalText.characters).isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: String(finalText.characters)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        // show more information about the mic
                        if let micInput {
                            print(micInput)
                        }
                    } label: {
                        Image(systemName: micInput?.portIcon ?? "mic")
                            .contentTransition(.symbolEffect)
                    }
                }
            }
            .task(id: ObjectIdentifier(session)) {
                for await input in session.audioInputConfigurationStream {
                    withAnimation {
                        micInput = input
                    }
                }
            }
#endif
            .task(id: ObjectIdentifier(session)) {
                for await newStatus in session.statusStream {
                    status = newStatus
                }
            }
            .task(id: SpeechDetectorTaskID(
                sessionID: ObjectIdentifier(session),
                vadEnabled: enableVAD,
                configurationID: vadConfigurationToken
            )) {
                guard enableVAD, let stream = session.speechDetectorResultsStream else {
                    await MainActor.run {
                        isSpeechDetected = true
                    }
                    return
                }

                for await result in stream {
                    await MainActor.run {
                        withAnimation {
                            isSpeechDetected = result.speechDetected
                        }
                    }
                }
            }
        }
        .onChange(of: enableVAD) { _, newValue in
            Task { @MainActor in
                if newValue {
                    session.configureVoiceActivation(
                        detectionOptions: .init(sensitivityLevel: vadSensitivity),
                        reportResults: true
                    )
                } else {
                    session.disableVoiceActivation()
                }
                isSpeechDetected = true
                vadConfigurationToken = UUID()
            }
        }
        .onChange(of: vadSensitivity) { _, newLevel in
            guard enableVAD else { return }
            Task { @MainActor in
                session.configureVoiceActivation(
                    detectionOptions: .init(sensitivityLevel: newLevel),
                    reportResults: true
                )
                vadConfigurationToken = UUID()
            }
        }
        .onChange(of: logLevel) { _, newValue in
            SpeechSession.logging = newValue
        }
        .onChange(of: presetChoice) { _, newChoice in
            Task { @MainActor in
                let previousSession = session

                transcriptionTask?.cancel()
                transcriptionTask = nil

                if status != .idle, status != .stopping {
                    await previousSession.stopTranscribing()
                }

                session = makeSession(for: newChoice)
                status = .idle
                finalText = ""
                partialText = ""
                error = nil
            }
        }
        .onDisappear {
            handleStopAction()
        }
    }

}

private struct SpeechDetectorTaskID: Hashable {
    let sessionID: ObjectIdentifier
    let vadEnabled: Bool
    let configurationID: UUID
}

private extension TranscriptionView {
    func handlePrimaryAction() {
        switch status {
        case .idle:
            startSession()
        case .preparing:
            handleStopAction()
        case .transcribing:
            Task { @MainActor in
                await session.pauseTranscribing()
            }
        case .paused:
            Task { @MainActor in
                do {
                    try await session.resumeTranscribing()
                } catch {
                    self.error = error.localizedDescription
                }
            }
        case .stopping:
            break
        }
    }

    func handleStopAction() {
        Task { @MainActor in
            await session.stopTranscribing()
            self.partialText = ""
        }
        transcriptionTask?.cancel()
        transcriptionTask = nil
    }

    func startSession() {
        error = nil
        finalText = ""
        partialText = ""

        transcriptionTask?.cancel()
        transcriptionTask = Task { @MainActor in
            do {
                for try await result in session.startTranscribing() {
                    result.apply(
                        to: &finalText,
                        partialText: &partialText
                    )
                }
            } catch is CancellationError {
                // Ignore cancellations triggered by stop action
            } catch {
                self.error = error.localizedDescription
            }
            self.partialText = ""
            self.transcriptionTask = nil
        }
    }

    var buttonColor: Color {
        switch status {
        case .idle:
            return Color.indigo
        case .preparing:
            return Color.orange
        case .transcribing:
            return Color.red
        case .paused:
            return Color.yellow
        case .stopping:
            return Color.gray
        }
    }

    var buttonIcon: String {
        switch status {
        case .idle:
            return "mic.fill"
        case .preparing:
            return "hourglass"
        case .transcribing:
            return "pause.fill"
        case .paused:
            return "play.fill"
        case .stopping:
            return "stop.fill"
        }
    }

    var showStopButton: Bool {
        switch status {
        case .idle, .stopping:
            return false
        case .preparing, .transcribing, .paused:
            return true
        }
    }

    var statusMessage: String {
        switch status {
        case .idle:
            return "Tap to start"
        case .preparing:
            return "Preparing session..."
        case .transcribing:
            return "Listening..."
        case .paused:
            return "Paused — tap to resume or stop"
        case .stopping:
            return "Stopping..."
        }
    }

    func makeSession(for choice: DemoTranscriberPreset) -> SpeechSession {
        let newSession = SpeechSession(preset: choice.preset)
        if enableVAD {
            newSession.configureVoiceActivation(
                detectionOptions: .init(sensitivityLevel: vadSensitivity),
                reportResults: true
            )
        }
        return newSession
    }
}

#Preview {
    TranscriptionView()
}
