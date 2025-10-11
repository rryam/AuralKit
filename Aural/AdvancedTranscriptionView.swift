import SwiftUI
import AuralKit
import Speech

// MARK: - Sub-views

struct TranscriptContentView: View {
    let finalizedText: AttributedString
    let volatileText: AttributedString
    let currentTimeRange: String
    let status: SpeechSession.Status

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !finalizedText.characters.isEmpty {
                Text(finalizedText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
            }

            if !volatileText.characters.isEmpty {
                VolatileTextView(
                    volatileText: volatileText,
                    currentTimeRange: currentTimeRange
                )
            }

            if finalizedText.characters.isEmpty &&
                volatileText.characters.isEmpty &&
                status == .idle {
                EmptyStateView()
            }
        }
        .padding()
    }
}

struct VolatileTextView: View {
    let volatileText: AttributedString
    let currentTimeRange: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text(volatileText)
                    .font(.body)
                    .italic()
            }

            if !currentTimeRange.isEmpty {
                Label(currentTimeRange, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.indigo.opacity(0.1))
        .cornerRadius(12)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.circle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Tap the button below to start transcribing")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }
}

struct LanguageSelectorView: View {
    @Bindable var manager: TranscriptionManager
    let commonLocales: [Locale]

    var body: some View {
        HStack {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
            Text("Language:")
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(commonLocales, id: \.identifier) { locale in
                    Button {
                        manager.selectedLocale = locale
                    } label: {
                        HStack {
                            Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            if locale == manager.selectedLocale {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(
                        manager.selectedLocale.localizedString(
                            forIdentifier: manager.selectedLocale.identifier
                        ) ?? manager.selectedLocale.identifier
                    )
                    .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal)
    }
}

struct PresetSelectorView: View {
    @Bindable var manager: TranscriptionManager

    var body: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.secondary)
            Text("Preset:")
                .foregroundStyle(.secondary)
            Spacer()
            Picker("Preset", selection: $manager.selectedPreset) {
                ForEach(DemoTranscriberPreset.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.horizontal)
    }
}

struct RecordButtonView: View {
    let status: SpeechSession.Status
    let isDisabled: Bool
    let primaryAction: () -> Void
    let stopAction: () -> Void
    @Binding var animationScale: CGFloat

    var body: some View {
        VStack(spacing: 12) {
            Button(action: primaryAction) {
                ZStack {
                    Circle()
                        .fill(buttonColor)
                        .frame(width: 80, height: 80)
                        .scaleEffect(animationScale)

                    Image(systemName: buttonIcon)
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, isActive: status == .preparing)
                }
            }
            .disabled(isDisabled || status == .stopping)

            if showsStopButton {
                Button("Stop", action: stopAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.gray)
                    .disabled(status == .stopping)
            }
        }
    }

    private var buttonColor: Color {
        switch status {
        case .idle:
            return Color.blue
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

    private var showsStopButton: Bool {
        switch status {
        case .idle, .stopping:
            return false
        case .preparing, .transcribing, .paused:
            return true
        }
    }
}

struct ErrorView: View {
    let error: String

    var body: some View {
        Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
    }
}

struct ControlsView: View {
    @Bindable var manager: TranscriptionManager
    @Binding var animationScale: CGFloat
    let commonLocales: [Locale]

    var body: some View {
        VStack(spacing: 20) {
            PresetSelectorView(manager: manager)
            LanguageSelectorView(
                manager: manager,
                commonLocales: commonLocales
            )

            RecordButtonView(
                status: manager.status,
                isDisabled: manager.error != nil,
                primaryAction: manager.primaryAction,
                stopAction: manager.stopTranscription,
                animationScale: $animationScale
            )

            Text(statusMessage(for: manager.status))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom)
        }
        .padding(.vertical)
        #if os(iOS)
        .background(Color(UIColor.systemBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
        .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
    }

    private func statusMessage(for status: SpeechSession.Status) -> String {
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

// MARK: - Main View

struct AdvancedTranscriptionView: View {
    @Bindable var manager: TranscriptionManager
    @State private var animationScale: CGFloat = 1.0
    @State private var showPermissionsAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Transcript Display
                ScrollView {
                    TranscriptContentView(
                        finalizedText: manager.finalizedText,
                        volatileText: manager.volatileText,
                        currentTimeRange: manager.currentTimeRange,
                        status: manager.status
                    )
                }
                .frame(maxHeight: .infinity)

                // Error Display
                if let error = manager.error {
                    ErrorView(error: error)
                }

                // Controls
                ControlsView(
                    manager: manager,
                    animationScale: $animationScale,
                    commonLocales: commonLocales
                )
            }
            .navigationTitle("AuralKit Demo")
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
#endif
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    if !manager.currentTranscript.isEmpty {
                        ShareLink(item: manager.currentTranscript) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }

                    Menu {
                        Label("iOS 26+ Features Active", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            updateAnimation(for: manager.status)
        }
        .onChange(of: manager.status) { _, status in
            updateAnimation(for: status)
        }
    }

    var commonLocales: [Locale] {
        [
            Locale(identifier: "en-US"),
            Locale(identifier: "es-ES"),
            Locale(identifier: "fr-FR"),
            Locale(identifier: "de-DE"),
            Locale(identifier: "it-IT"),
            Locale(identifier: "pt-BR"),
            Locale(identifier: "zh-CN"),
            Locale(identifier: "ja-JP"),
            Locale(identifier: "ko-KR")
        ]
    }

    private func updateAnimation(for status: SpeechSession.Status) {
        let isActive = status == .transcribing
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            animationScale = isActive ? 1.2 : 1.0
        }
    }
}
