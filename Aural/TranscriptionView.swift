import SwiftUI
import AuralKit

/// Minimal example showing how easy SpeechSession is to use
struct TranscriptionView: View {
    @State private var session = SpeechSession()
    @State private var finalText: AttributedString = ""
    @State private var partialText: AttributedString = ""
#if os(iOS)
    @State private var micInput: AudioInputInfo?
#endif
    @State private var status: SpeechSession.Status = .idle
    @State private var error: String?
    @State private var transcriptionTask: Task<Void, Never>?

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
            .task {
                for await input in session.audioInputConfigurationStream {
                    withAnimation {
                        micInput = input
                    }
                }
            }
#endif
            .task {
                let stream = await MainActor.run { session.statusStream }
                for await newStatus in stream {
                    await MainActor.run {
                        status = newStatus
                    }
                }
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
            Task {
                await session.pauseTranscribing()
            }
        case .paused:
            Task {
                do {
                    try await session.resumeTranscribing()
                } catch {
                    await MainActor.run {
                        self.error = error.localizedDescription
                    }
                }
            }
        case .stopping:
            break
        }
    }

    private func handleStopAction() {
        Task {
            await session.stopTranscribing()
            await MainActor.run {
                self.partialText = ""
            }
        }
        transcriptionTask?.cancel()
        transcriptionTask = nil
    }

    private func startSession() {
        error = nil
        finalText = ""
        partialText = ""

        transcriptionTask?.cancel()
        transcriptionTask = Task {
            do {
                for try await result in session.startTranscribing() {
                    await MainActor.run {
                        result.apply(
                            to: &finalText,
                            partialText: &partialText
                        )
                    }
                }
            } catch is CancellationError {
                // Ignore cancellations triggered by stop action
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }
            await MainActor.run {
                self.partialText = ""
                self.transcriptionTask = nil
            }
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
}

#Preview {
    TranscriptionView()
}
