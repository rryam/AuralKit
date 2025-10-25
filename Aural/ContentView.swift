import SwiftUI
import AuralKit

struct ContentView: View {
    private enum DemoTab: Hashable {
        case quickStart
        case advanced
        case customVocabulary
        case history
        case settings
    }

    @State private var selectedTab: DemoTab = .quickStart
    @State private var transcriptionManager = TranscriptionManager()

    var body: some View {
        TabView(selection: $selectedTab) {
            TranscriptionView()
                .tabItem {
                    Label("Quick Start", systemImage: "bolt.waveform")
                }
                .tag(DemoTab.quickStart)

            AdvancedTranscriptionView(manager: transcriptionManager)
                .tabItem {
                    Label("Advanced", systemImage: "mic.circle.fill")
                }
                .tag(DemoTab.advanced)

            CustomVocabularyDemoView()
                .tabItem {
                    Label("Vocabulary", systemImage: "text.badge.plus")
                }
                .tag(DemoTab.customVocabulary)

            HistoryView(manager: transcriptionManager)
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(DemoTab.history)

            SettingsView(manager: transcriptionManager)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(DemoTab.settings)
        }
    }
}

#Preview {
    ContentView()
}
