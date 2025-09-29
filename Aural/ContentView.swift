import SwiftUI
import AuralKit

struct ContentView: View {
    @State private var transcriptionManager = TranscriptionManager()
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            TranscriptionView(manager: transcriptionManager)
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
    }
}

#Preview {
    ContentView()
}