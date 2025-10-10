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

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transcriber Preset")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Transcriber Preset", selection: $presetChoice) {
                            ForEach(DemoTranscriberPreset.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Voice Activity Detection", isOn: $enableVAD)
                            .font(.subheadline)
                        
                        if enableVAD {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sensitivity Level")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("Sensitivity", selection: $vadSensitivity) {
                                    Text("Low").tag(SpeechDetector.SensitivityLevel.low)
                                    Text("Medium").tag(SpeechDetector.SensitivityLevel.medium)
                                    Text("High").tag(SpeechDetector.SensitivityLevel.high)
                                }
                                .pickerStyle(.segmented)
                                
                                Text("Speech detected: \(isSpeechDetected ? "Yes" : "No")")
                                    .font(.caption)
                                    .foregroundStyle(isSpeechDetected ? .green : .orange)
                                    .padding(.top, 4)
                            }
                            .padding(.leading, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !finalText.characters.isEmpty {
                            Text(finalText)
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                        }

                        if !partialText.characters.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(partialText)
                                    .font(.body)
                                    .italic()
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.indigo.opacity(0.1))
                            .cornerRadius(12)
                        }

                    }
                    .padding()
                }

                Spacer()

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }

                Button {
                    handlePrimaryAction()
                } label: {
                    ZStack {
                        Circle()
                            .fill(buttonColor)
                            .frame(width: 80, height: 80)
                        Image(systemName: buttonIcon)
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                    }
                }
                .disabled(error != nil || status == .stopping)

                if showStopButton {
                    Button("Stop") {
                        handleStopAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray)
                }

                Text(statusMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 32)
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
            .task(id: ObjectIdentifier(session)) {
                guard enableVAD else { return }
                guard let stream = session.speechDetectorResultsStream else { return }
                for await result in stream {
                    withAnimation {
                        isSpeechDetected = result.speechDetected
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
            }
        }
        .onChange(of: vadSensitivity) { _, newLevel in
            guard enableVAD else { return }
            Task { @MainActor in
                session.configureVoiceActivation(
                    detectionOptions: .init(sensitivityLevel: newLevel),
                    reportResults: true
                )
            }
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
    }

    private func handlePrimaryAction() {
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

    private func handleStopAction() {
        Task { @MainActor in
            await session.stopTranscribing()
            self.partialText = ""
        }
        transcriptionTask?.cancel()
        transcriptionTask = nil
    }

    private func startSession() {
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

    private var buttonColor: Color {
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

    private var buttonIcon: String {
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

    private var showStopButton: Bool {
        switch status {
        case .idle, .stopping:
            return false
        case .preparing, .transcribing, .paused:
            return true
        }
    }

    private var statusMessage: String {
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

    private func makeSession(for choice: DemoTranscriberPreset) -> SpeechSession {
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
