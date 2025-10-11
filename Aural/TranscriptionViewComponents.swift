import SwiftUI
import AuralKit
import Speech

// MARK: - Settings Controls

struct TranscriptionSettingsView: View {
    @Binding var presetChoice: DemoTranscriberPreset
    @Binding var enableVAD: Bool
    @Binding var vadSensitivity: SpeechDetector.SensitivityLevel
    @Binding var isSpeechDetected: Bool
    @Binding var logLevel: SpeechSession.LogLevel

    var body: some View {
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

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Logging Level")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Logging Level", selection: $logLevel) {
                    ForEach(SpeechSession.LogLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
}

// MARK: - Transcription Display

struct TranscriptionTextView: View {
    let finalText: AttributedString
    let partialText: AttributedString

    var body: some View {
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
    }
}

// MARK: - Control Buttons

struct TranscriptionControlsView: View {
    let status: SpeechSession.Status
    let error: String?
    let showStopButton: Bool
    let buttonColor: Color
    let buttonIcon: String
    let statusMessage: String
    let onPrimaryAction: () -> Void
    let onStopAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }

            Button(action: onPrimaryAction) {
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
                Button("Stop", action: onStopAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.gray)
            }

            Text(statusMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.bottom, 32)
        }
    }
}
