import SwiftUI
import AuralKit
import Speech

struct SettingsView: View {
    @Bindable var manager: TranscriptionManager
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Transcription Options") {
                    Label("iOS 26 features enabled", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)

                    Picker("Transcriber Preset", selection: $manager.selectedPreset) {
                        ForEach(DemoTranscriberPreset.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }

                Section("Default Language") {
                    HStack {
                        Text("Language")
                        Spacer()
                        Text(
                            manager.selectedLocale.localizedString(
                                forIdentifier: manager.selectedLocale.identifier
                            ) ?? manager.selectedLocale.identifier
                        )
                        .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    Button {
                        showingAbout = true
                    } label: {
                        HStack {
                            Text("About AuralKit")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    Link(destination: URL(string: "https://github.com/rryam/AuralKit")!) {
                        HStack {
                            Label("View on GitHub", systemImage: "link")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                    }
                }

                Section {
                    VStack(spacing: 8) {
                        Text("AuralKit Demo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Version 1.0.0")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
        }
    }
}
