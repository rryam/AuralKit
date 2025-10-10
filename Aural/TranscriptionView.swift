import SwiftUI
import AuralKit

/// Minimal example showing how easy SpeechSession is to use
struct TranscriptionView: View {
    @State private var session = SpeechSession()
    @State private var presetChoice: DemoTranscriberPreset = .manual
    @State private var finalText: AttributedString = ""
    @State private var partialText: AttributedString = ""
#if os(iOS)
    @State private var micInput: AudioInputInfo?
#endif
    @State private var isTranscribing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
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
                    toggleTranscription()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.indigo)
                            .frame(width: 80, height: 80)

                        Image(systemName: isTranscribing ? "stop.fill" : "mic.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                    }
                }
                .disabled(error != nil)

                Text(isTranscribing ? "Listening..." : "Tap to start")
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
        }
        .onChange(of: presetChoice) { _, newChoice in
            Task {
                await session.stopTranscribing()
                await MainActor.run {
                    isTranscribing = false
                    finalText = ""
                    partialText = ""
                    error = nil
                    session = makeSession(for: newChoice)
                }
            }
        }
    }

    func toggleTranscription() {
        if isTranscribing {
            Task {
                await session.stopTranscribing()
                isTranscribing = false
                partialText = ""
            }
        } else {
            isTranscribing = true
            error = nil
            finalText = ""
            partialText = ""

            Task {
                do {
                    for try await result in session.startTranscribing() {
                        result.apply(
                            to: &finalText,
                            partialText: &partialText
                        )
                    }
                } catch {
                    self.error = error.localizedDescription
                }
                partialText = ""
                isTranscribing = false
            }
        }
    }

    private func makeSession(for choice: DemoTranscriberPreset) -> SpeechSession {
        if let preset = choice.preset {
            return SpeechSession(preset: preset)
        } else {
            return SpeechSession()
        }
    }
}

#Preview {
    TranscriptionView()
}
