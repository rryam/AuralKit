import SwiftUI
import AuralKit
import Speech

struct CustomVocabularyDemoView: View {
    @StateObject private var viewModel = CustomVocabularyDemoViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    configurationSection
                    vocabularySection
                    pronunciationsSection
                    contextualStringsSection
                    statusSection
                    transcriptionOutputSection
                    controlSection
                }
                .padding()
            }
            .navigationTitle("Custom Vocabulary")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack {
                        Text("Custom Vocabulary")
                            .font(.headline)
                        Text("Tech Demo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
                            Text("Count: \(phrase.count.wrappedValue)")
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

    var transcriptionOutputSection: some View {
        GroupBox("Transcription") {
            VStack(alignment: .leading, spacing: 12) {
                if !viewModel.finalText.characters.isEmpty {
                    Text(viewModel.finalText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.thinMaterial)
                        .cornerRadius(8)
                }

                if !viewModel.partialText.characters.isEmpty {
                    Text(viewModel.partialText)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.indigo.opacity(0.1))
                        .cornerRadius(8)
                }

                if viewModel.finalText.characters.isEmpty && viewModel.partialText.characters.isEmpty {
                    Text("Results will appear here once transcription begins.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var controlSection: some View {
        HStack(spacing: 16) {
            Button(action: viewModel.startTranscription) {
                Label(viewModel.startButtonTitle, systemImage: viewModel.startButtonIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isStartDisabled)

            Button(action: viewModel.stopTranscription) {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isStopDisabled)
        }
        .padding(.top, 8)
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
