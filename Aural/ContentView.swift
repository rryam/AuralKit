import SwiftUI
import AuralKit

struct ContentView: View {
    private enum DemoTab: Hashable {
        case transcribe
        case customVocabulary
        case history
        case settings
    }

    @State private var selectedTab: DemoTab = .transcribe
    @State private var transcriptionManager = TranscriptionManager()

    var body: some View {
        TabView(selection: $selectedTab) {
            TranscriptionExperienceView(manager: transcriptionManager)
                .tabItem {
                    Label("Transcribe", systemImage: "waveform")
                }
                .tag(DemoTab.transcribe)

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
