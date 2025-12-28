import SwiftUI
import Observation
import AuralKit
import Speech

struct CustomVocabularyDemoView: View {
    @State private var model = CustomVocabularyDemoViewModel()

    var body: some View {
        NavigationStack {
            @Bindable var viewModel = model
            VStack(spacing: 32) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        TranscriptionTextView(
                            finalText: viewModel.finalText,
                            partialText: viewModel.partialText,
                            currentTimeRange: viewModel.currentTimeRange.isEmpty ? nil : viewModel.currentTimeRange
                        )
                        configurationSection(viewModel)
                        vocabularySection(viewModel)
                        pronunciationsSection(viewModel)
                        contextualStringsSection(viewModel)
                        statusSection(viewModel)
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
            .navigationTitle("Custom Vocabulary")
        }
        .onDisappear {
            model.teardown()
        }
    }
}

// MARK: - Sections

private extension CustomVocabularyDemoView {
    func configurationSection(@Bindable _ viewModel: CustomVocabularyDemoViewModel) -> some View {
        GroupBox("Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Custom Vocabulary", isOn: $viewModel.isCustomVocabularyEnabled)
                    .onChange(of: model.isCustomVocabularyEnabled) { _, enabled in
                        model.handleToggleChange(enabled)
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
                        Slider(value: $viewModel.vocabularyWeight, in: 0.0...1.0, step: 0.05)
                        Text(viewModel.vocabularyWeight.formatted(.number.precision(.fractionLength(2))))
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }

                    Button("Reset to Tech Demo") {
                        model.resetToPreset()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func vocabularySection(@Bindable _ viewModel: CustomVocabularyDemoViewModel) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $viewModel.phrasesEnabled) {
                    Label("Phrases", systemImage: viewModel.phrasesEnabled ? "checkmark.circle.fill" : "circle")
                        .labelStyle(.titleAndIcon)
                }

                if viewModel.phrasesEnabled {
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
                        model.phrases.append(.init(text: "", count: 3))
                    } label: {
                        Label("Add Phrase", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func pronunciationsSection(@Bindable _ viewModel: CustomVocabularyDemoViewModel) -> some View {
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
                    model.pronunciations.append(.init(grapheme: "", phonemes: []))
                } label: {
                    Label("Add Pronunciation", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func contextualStringsSection(@Bindable _ viewModel: CustomVocabularyDemoViewModel) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $viewModel.contextualStringsEnabled) {
                    Label(
                        "Contextual Strings",
                        systemImage: viewModel.contextualStringsEnabled ? "checkmark.circle.fill" : "circle"
                    )
                    .labelStyle(.titleAndIcon)
                }

                if viewModel.contextualStringsEnabled {
                    Text("Comma-separated list to further bias recognition.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField(
                        "GraphQL, Static Analysis, Zero-Knowledge",
                        text: $viewModel.contextualTerms,
                        axis: .vertical
                    )
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func statusSection(@Bindable _ viewModel: CustomVocabularyDemoViewModel) -> some View {
        GroupBox("Status") {
            VStack(alignment: .leading, spacing: 8) {
                statusRow(title: "Session", value: model.statusTitleText)

                if let cacheKey = model.cacheKey {
                    statusRow(title: "Cache Key", value: cacheKey)
                }

                if let duration = model.compilationDuration {
                    statusRow(
                        title: "Compilation",
                        value: String(format: "%.2f s", duration)
                    )
                }

                if model.isCompiling {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Preparing custom vocabulary…")
                    }
                }

                if let progressFraction = model.progressFraction {
                    VStack(alignment: .leading) {
                        Text("Downloading dictation assets…")
                        ProgressView(value: progressFraction)
                            .progressViewStyle(.linear)
                    }
                }

                if let message = model.errorMessage {
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
        switch model.status {
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
        switch model.status {
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
        switch model.status {
        case .idle, .stopping:
            return false
        case .preparing, .transcribing, .paused:
            return true
        }
    }

    var statusMessage: String {
        switch model.status {
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
        switch model.status {
        case .idle:
            model.startTranscription()
        case .preparing:
            model.stopTranscription()
        case .transcribing:
            model.pauseTranscription()
        case .paused:
            model.resumeTranscription()
        case .stopping:
            break
        }
    }

    func handleStopAction() {
        model.stopTranscription()
    }
}
