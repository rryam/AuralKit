import SwiftUI
import AuralKit

/// Minimal example showing how easy SpeechSession is to use
struct MinimalTranscriptionView: View {
    @State private var session = SpeechSession()
    @State private var finalText: AttributedString = ""
    @State private var partialText: AttributedString = ""
    @State private var isTranscribing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Transcript Display
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
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                        }

                        if finalText.characters.isEmpty && partialText.characters.isEmpty && !isTranscribing {
                            VStack(spacing: 12) {
                                Image(systemName: "mic.circle")
                                    .font(.system(size: 60))
                                    .foregroundColor(.secondary)
                                Text("Tap the microphone button below to start")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                        }
                    }
                    .padding()
                }

                Spacer()

                // Error Display
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }

                // Record Button
                Button {
                    toggleTranscription()
                } label: {
                    ZStack {
                        Circle()
                            .fill(isTranscribing ? Color.red : Color.blue)
                            .frame(width: 80, height: 80)

                        Image(systemName: isTranscribing ? "stop.fill" : "mic.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                    }
                }
                .disabled(error != nil)

                Text(isTranscribing ? "Listening..." : "Tap to start")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 32)
            }
            .background(TopGradientView())
            .navigationTitle("Aural")
            .toolbar {
                if !String(finalText.characters).isEmpty {
                    ShareLink(item: String(finalText.characters)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    func toggleTranscription() {
        if isTranscribing {
            // Stop transcription
            Task {
                await session.stopTranscribing()
                isTranscribing = false
            }
        } else {
            // Start transcription
            isTranscribing = true
            error = nil
            finalText = ""
            partialText = ""

            Task {
                do {
                    for try await result in session.startTranscribing() {
                        if result.isFinal {
                            finalText += result.text
                            partialText = ""
                        } else {
                            partialText = result.text
                        }
                    }
                } catch {
                    self.error = error.localizedDescription
                }
                isTranscribing = false
            }
        }
    }
}

#Preview {
    MinimalTranscriptionView()
}