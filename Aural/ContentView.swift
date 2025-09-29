import SwiftUI
import AuralKit

struct ContentView: View {
    @State private var showAdvanced = false

    var body: some View {
        Group {
            if showAdvanced {
                AdvancedContentView(showAdvanced: $showAdvanced)
            } else {
                TranscriptionView()
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Button("Advanced") {
                                showAdvanced = true
                            }
                        }
                    }
            }
        }
    }
}

/// Advanced demo with language selection, history, and settings
struct AdvancedContentView: View {
    @Binding var showAdvanced: Bool
    @State private var transcriptionManager = TranscriptionManager()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            AdvancedTranscriptionView(manager: transcriptionManager)
                .tabItem {
                    Label("Transcribe", systemImage: "mic.circle.fill")
                }
                .tag(0)

            HistoryView(manager: transcriptionManager)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(1)

            SettingsView(manager: transcriptionManager)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Simple") {
                    showAdvanced = false
                }
            }
        }
    }
}

#Preview("Minimal") {
    ContentView()
}

#Preview("Advanced") {
    AdvancedContentView(showAdvanced: .constant(true))
}