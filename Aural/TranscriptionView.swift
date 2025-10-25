import SwiftUI
import AuralKit
import Speech

struct TranscriptionView: View {
    @Bindable var manager: TranscriptionManager
    @State private var animationScale: CGFloat = 1.0

    private let preferredLocales: [Locale] = [
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                settingsSection

                TranscriptionTextView(
                    finalText: manager.finalizedText,
                    partialText: manager.volatileText,
                    currentTimeRange: manager.currentTimeRange.isEmpty ? nil : manager.currentTimeRange,
                    emptyStateMessage: "Press the microphone to begin live transcription."
                )
                .padding(.horizontal)

                Spacer(minLength: 0)

                TranscriptionControlsView(
                    status: manager.status,
                    error: manager.error,
                    showStopButton: showStopButton,
                    buttonColor: buttonColor,
                    buttonIcon: buttonIcon,
                    statusMessage: statusMessage,
                    onPrimaryAction: { manager.primaryAction() },
                    onStopAction: { manager.stopTranscription() },
                    animationScale: animationScale
                )
                .padding(.horizontal)
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity)
            .background(TopGradientView())
            .navigationTitle("Transcribe")
#if os(iOS)
            .navigationBarTitleDisplayMode(.large)
#endif
            .toolbar { toolbarContent }
#if os(macOS)
            .toolbarVisibility(.visible, for: .automatic)
#endif
        }
        .onAppear {
            SpeechSession.logging = .debug
            updateAnimation(for: manager.status)
        }
        .onChange(of: manager.status) { _, status in
            updateAnimation(for: status)
        }
    }

    private var settingsSection: some View {
        VStack(spacing: 16) {
            TranscriptionSettingsView(
                presetChoice: $manager.selectedPreset,
                enableVAD: $manager.isVoiceActivationEnabled,
                vadSensitivity: $manager.voiceActivationSensitivity,
                isSpeechDetected: manager.isSpeechDetected
            )

            GroupBox("Preferred Locale") {
                LanguageSelector(manager: manager, locales: preferredLocales)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !manager.currentTranscript.isEmpty {
#if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    manager.clearText()
                } label: {
                    Image(systemName: "trash")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: manager.currentTranscript) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
#else
            ToolbarItem(placement: .automatic) {
                Button {
                    manager.clearText()
                } label: {
                    Image(systemName: "trash")
                }
            }
            ToolbarItem(placement: .automatic) {
                ShareLink(item: manager.currentTranscript) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
#endif
        }

#if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            Button {
                if let micInput = manager.micInput {
                    print(micInput)
                }
            } label: {
                Image(systemName: manager.micInput?.portIcon ?? "mic")
                    .contentTransition(.symbolEffect)
            }
        }
#endif
    }

    private func updateAnimation(for status: SpeechSession.Status) {
        let isActive = status == .transcribing
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            animationScale = isActive ? 1.2 : 1.0
        }
    }

    private var buttonColor: Color {
        switch manager.status {
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

    private var buttonIcon: String {
        switch manager.status {
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
        switch manager.status {
        case .idle, .stopping:
            return false
        case .preparing, .transcribing, .paused:
            return true
        }
    }

    private var statusMessage: String {
        switch manager.status {
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
}

private struct LanguageSelector: View {
    @Bindable var manager: TranscriptionManager
    let locales: [Locale]

    var body: some View {
        HStack {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
            Text("Locale")
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(locales, id: \.identifier) { locale in
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
                HStack(spacing: 6) {
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
                .background(Color.gray.opacity(0.12))
                .cornerRadius(8)
            }
        }
    }
}
