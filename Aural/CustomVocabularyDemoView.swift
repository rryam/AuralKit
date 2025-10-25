import SwiftUI
import AuralKit
import Speech
import CryptoKit

struct CustomVocabularyDemoView: View {
    @State var session = SpeechSession()
    @State var status: SpeechSession.Status = .idle
    @State var finalText: AttributedString = ""
    @State var partialText: AttributedString = ""
    @State var errorMessage: String?
    @State var isCustomVocabularyEnabled = true
    @State var vocabularyIdentifier = "tech-demo"
    @State var vocabularyVersion = "1"
    @State var vocabularyWeight = 0.6
    @State var phrases: [CustomVocabularyPhrase] = CustomVocabularyPreset.techDemo.phrases
    @State var pronunciations: [CustomVocabularyPronunciation] = CustomVocabularyPreset.techDemo.pronunciations
    @State var contextualTerms = "WebAssembly, TensorFlow, Kubernetes"
    @State var isCompiling = false
    @State var cacheKey: String?
    @State var compilationDuration: TimeInterval?
    @State var transcriptionTask: Task<Void, Never>?
    @StateObject var progressObserver = CustomVocabularyProgressObserver()
    @State var progressTask: Task<Void, Never>?

    let locale = Locale(identifier: "en_US")

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
        .task(id: ObjectIdentifier(session)) {
            for await newStatus in session.statusStream {
                await MainActor.run {
                    status = newStatus
                }
            }
        }
        .onChange(of: isCustomVocabularyEnabled) { _, isEnabled in
            if !isEnabled, status == .transcribing || status == .preparing {
                stopTranscription()
            }
        }
        .onDisappear {
            stopTranscription()
        }
    }
}

// MARK: - Sections

private extension CustomVocabularyDemoView {
    var configurationSection: some View {
        GroupBox("Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Custom Vocabulary", isOn: $isCustomVocabularyEnabled)

                if isCustomVocabularyEnabled {
                    HStack {
                        TextField("Identifier", text: $vocabularyIdentifier)
#if os(iOS)
                            .textInputAutocapitalization(.never)
#endif
                        TextField("Version", text: $vocabularyVersion)
#if os(iOS)
                            .textInputAutocapitalization(.never)
#endif
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Weight")
                        Slider(value: $vocabularyWeight, in: 0.0...1.0)
                        Text(vocabularyWeight.formatted(.number.precision(.fractionLength(2))))
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }

                    Button("Reset to Tech Demo") {
                        phrases = CustomVocabularyPreset.techDemo.phrases
                        pronunciations = CustomVocabularyPreset.techDemo.pronunciations
                        vocabularyIdentifier = "tech-demo"
                        vocabularyVersion = "1"
                        vocabularyWeight = 0.6
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
                ForEach($phrases) { phrase in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Phrase", text: phrase.text)
                        Stepper(value: phrase.count, in: 1...20) {
                            Text("Count: \(phrase.count.wrappedValue)")
                        }
                        Divider()
                    }
                }

                Button {
                    phrases.append(.init(text: "", count: 3))
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
                ForEach($pronunciations) { pronunciation in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Grapheme", text: pronunciation.grapheme)
                        TextField("Phonemes (space separated)", text: pronunciation.phonemeText)
                        Divider()
                    }
                }

                Button {
                    pronunciations.append(.init(grapheme: "", phonemes: []))
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
                TextField("GraphQL, Static Analysis, Zero-Knowledge", text: $contextualTerms, axis: .vertical)
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
                statusRow(title: "Session", value: statusTitle)

                if let cacheKey {
                    statusRow(title: "Cache Key", value: cacheKey)
                }

                if let duration = compilationDuration {
                    statusRow(
                        title: "Compilation",
                        value: String(format: "%.2f s", duration)
                    )
                }

                if isCompiling {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Preparing custom vocabulary…")
                    }
                }

                if let progressFraction = progressObserver.progressFraction {
                    VStack(alignment: .leading) {
                        Text("Downloading dictation assets…")
                        ProgressView(value: progressFraction)
                            .progressViewStyle(.linear)
                    }
                }

                if let message = errorMessage {
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
                if !finalText.characters.isEmpty {
                    Text(finalText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.thinMaterial)
                        .cornerRadius(8)
                }

                if !partialText.characters.isEmpty {
                    Text(partialText)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.indigo.opacity(0.1))
                        .cornerRadius(8)
                }

                if finalText.characters.isEmpty && partialText.characters.isEmpty {
                    Text("Results will appear here once transcription begins.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var controlSection: some View {
        HStack(spacing: 16) {
            Button(action: startTranscription) {
                Label(startButtonTitle, systemImage: startButtonIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCompiling || status == .preparing || status == .transcribing)

            Button(action: stopTranscription) {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(status == .idle || status == .stopping)
        }
        .padding(.top, 8)
    }
}
