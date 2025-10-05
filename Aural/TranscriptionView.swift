import SwiftUI
import AuralKit

/// Minimal example showing how easy SpeechSession is to use
struct TranscriptionView: View {
    @State private var session = SpeechSession()
    @State private var finalText: AttributedString = ""
    @State private var partialText: AttributedString = ""
    @State private var isTranscribing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
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
            Task {
                await session.stopTranscribing()
                isTranscribing = false
            }
        } else {
            isTranscribing = true
            error = nil
            finalText = ""
            partialText = ""

            Task {
                do {
                    let stream = await session.startTranscribing()
                    for try await result in stream {
                        result.apply(
                            to: &finalText,
                            partialText: &partialText
                        )
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
    TranscriptionView()
}
