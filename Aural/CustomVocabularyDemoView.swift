import SwiftUI
import AuralKit
import Speech

struct CustomVocabularyDemoView: View {
    @StateObject private var viewModel = CustomVocabularyDemoViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        TranscriptionTextView(
                            finalText: viewModel.finalText,
                            partialText: viewModel.partialText
                        )
                        configurationSection
                        vocabularySection
                        pronunciationsSection
                        contextualStringsSection
                        statusSection
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }

                TranscriptionControlsView(
                    status: viewModel.status,
                    error: viewModel.errorMessage,
                    showStopButton: showStopButton,
                    buttonColor: buttonColor,
                    buttonIcon: buttonIcon,
                    statusMessage: statusMessage,
                    onPrimaryAction: handlePrimaryAction,
                    onStopAction: handleStopAction
                )
                .padding(.horizontal)
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity)
            .background(TopGradientView())
            .navigationTitle("Custom Vocabulary")
        }
        .onDisappear {
            viewModel.teardown()
        }
    }
}

// MARK: - Sections

private extension CustomVocabularyDemoView {
    var configurationSection: some View {
        GroupBox("Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Custom Vocabulary", isOn: $viewModel.isCustomVocabularyEnabled)
                    .onChange(of: viewModel.isCustomVocabularyEnabled) { _, enabled in
                        viewModel.handleToggleChange(enabled)
                    }

                if viewModel.isCustomVocabularyEnabled {
                    HStack {
                        TextField("Identifier", text: $viewModel.vocabularyIdentifier)
#if os(iOS)
                            .textInputAutocapitalization(.never)
#endif
                        TextField("Version", text: $viewModel.vocabularyVersion)
#if os(iOS)
                            .textInputAutocapitalization(.never)
#endif
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Weight")
                        Slider(value: $viewModel.vocabularyWeight, in: 0.0...1.0)
                        Text(viewModel.vocabularyWeight.formatted(.number.precision(.fractionLength(2))))
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }

                    Button("Reset to Tech Demo") {
                        viewModel.resetToPreset()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var vocabularySection: some View {
        GroupBox("Phrases") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach($viewModel.phrases) { phrase in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Phrase", text: phrase.text)
                        Stepper(value: phrase.count, in: 1...20) {
                            Text("Weight \(phrase.count.wrappedValue)")
                        }
                        Divider()
                    }
                }

                Button {
                    viewModel.phrases.append(.init(text: "", count: 3))
                } label: {
                    Label("Add Phrase", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var pronunciationsSection: some View {
        GroupBox("Pronunciations") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach($viewModel.pronunciations) { pronunciation in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Grapheme", text: pronunciation.grapheme)
                        TextField("Phonemes (space separated)", text: pronunciation.phonemeText)
                        Divider()
                    }
                }

                Button {
                    viewModel.pronunciations.append(.init(grapheme: "", phonemes: []))
                } label: {
                    Label("Add Pronunciation", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var contextualStringsSection: some View {
        GroupBox("Contextual Strings") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Comma-separated list to further bias recognition.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("GraphQL, Static Analysis, Zero-Knowledge", text: $viewModel.contextualTerms, axis: .vertical)
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var statusSection: some View {
        GroupBox("Status") {
            VStack(alignment: .leading, spacing: 8) {
                statusRow(title: "Session", value: viewModel.statusTitleText)

                if let cacheKey = viewModel.cacheKey {
                    statusRow(title: "Cache Key", value: cacheKey)
                }

                if let duration = viewModel.compilationDuration {
                    statusRow(
                        title: "Compilation",
                        value: String(format: "%.2f s", duration)
                    )
                }

                if viewModel.isCompiling {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Preparing custom vocabulary…")
                    }
                }

                if let progressFraction = viewModel.progressFraction {
                    VStack(alignment: .leading) {
                        Text("Downloading dictation assets…")
                        ProgressView(value: progressFraction)
                            .progressViewStyle(.linear)
                    }
                }

                if let message = viewModel.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .font(.footnote)
        }
    }
}

private extension CustomVocabularyDemoView {
    var buttonColor: Color {
        switch viewModel.status {
        case .idle:
            return .indigo
        case .preparing:
            return .orange
        case .transcribing:
            return .red
        case .paused:
            return .yellow
        case .stopping:
            return .gray
        }
    }

    var buttonIcon: String {
        switch viewModel.status {
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
        switch viewModel.status {
        case .idle, .stopping:
            return false
        case .preparing, .transcribing, .paused:
            return true
        }
    }

    var statusMessage: String {
        switch viewModel.status {
        case .idle:
            return "Ready"
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

    func handlePrimaryAction() {
        switch viewModel.status {
        case .idle:
            viewModel.startTranscription()
        case .preparing:
            viewModel.stopTranscription()
        case .transcribing:
            viewModel.pauseTranscription()
        case .paused:
            viewModel.resumeTranscription()
        case .stopping:
            break
        }
    }

    func handleStopAction() {
        viewModel.stopTranscription()
    }
}
