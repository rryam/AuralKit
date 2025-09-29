# AuralKit

![Swift](https://img.shields.io/badge/Swift-6.2+-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2026%2B%20|%20macOS%2026%2B-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)
[![GitHub release](https://img.shields.io/github/release/rryam/AuralKit.svg)](https://github.com/rryam/AuralKit/releases)

AuralKit is a simple, lightweight Swift wrapper for speech-to-text transcription using iOS 26's `SpeechTranscriber` and `SpeechAnalyzer` APIs while handling microphone capture, buffer conversion, model downloads, and cancellation on your behalf.

**Public API**: `SpeechSession` - A clean, session-based interface for speech transcription.

## Quick Start

```swift
import AuralKit

// Create a speech session with your preferred locale
let session = SpeechSession(locale: .current)

let streamTask = Task {
    do {
        // Start the async stream
        for try await result in session.startTranscribing() {
            if result.isFinal {
                print("Final: \(String(result.text.characters))")
            } else {
                print("Partial: \(String(result.text.characters))")
            }
        }
    } catch {
        print("Transcription failed: \(error)")
    }
}

// Later, when you want to stop capturing audio
Task {
    await session.stopTranscribing()
    await streamTask.value
}
```

## Installation

### Swift Package Manager

Add AuralKit to your project through Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/rryam/AuralKit`
3. Click Add Package

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/rryam/AuralKit", from: "1.0.0")
]
```

## Usage

### Simple Transcription

```swift
import AuralKit

// Create with default locale
let session = SpeechSession()

// Or specify a locale
let session = SpeechSession(locale: Locale(identifier: "es-ES"))

let streamTask = Task {
    do {
        // Start transcribing
        for try await attributedText in session.startTranscribing() {
            // Access the plain text
            let plainText = String(attributedText.characters)
            print(plainText)

            // Access timing metadata for each word/phrase
            for run in attributedText.runs {
                if let timeRange = run.audioTimeRange {
                    print("Text: \(run.text), Start: \(timeRange.start.seconds)s")
                }
            }
        }
    } catch {
        print("Transcription failed: \(error.localizedDescription)")
    }
}

// Stop when needed
Task {
    await session.stopTranscribing()
    await streamTask.value
}
```

## Demo App

Check out the included **Aural** demo app to see AuralKit in action! The demo showcases:

- **Live Transcription**: Real-time speech-to-text with visual feedback
- **Language Selection**: Switch between multiple locales
- **History Tracking**: View past transcriptions
- **Export & Share**: Share transcriptions via standard iOS share sheet

### Running the Demo

1. Open `Aural.xcodeproj` in the `Aural` directory
2. Build and run on your iOS 26+ device or simulator
3. Grant microphone and speech recognition permissions
4. Start transcribing!

### SwiftUI Example

```swift
import SwiftUI
import AuralKit

@available(iOS 26.0, *)
struct ContentView: View {
    @State private var auralKit = AuralKit()
    @State private var transcribedText = ""
    @State private var isTranscribing = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text(transcribedText.isEmpty ? "Tap to start..." : transcribedText)
                .padding()
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)

            Button(action: toggleTranscription) {
                Label(isTranscribing ? "Stop" : "Start", 
                      systemImage: isTranscribing ? "stop.circle.fill" : "mic.circle.fill")
                    .padding()
                    .background(isTranscribing ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
    
    func toggleTranscription() {
        if isTranscribing {
            Task {
                await session.stopTranscribing()
                isTranscribing = false
            }
        } else {
            isTranscribing = true
            Task {
                do {
                    for try await attributedText in session.startTranscribing() {
                        transcribedText = String(attributedText.characters)
                    }
                } catch {
                    print("Error: \(error)")
                }
                isTranscribing = false
            }
        }
    }
}

```

### Monitoring Model Downloads

When a locale has not been installed yet, AuralKit automatically downloads the appropriate speech model. You can observe download progress through the `modelDownloadProgress` property:

```swift
let kit = AuralKit(locale: Locale(identifier: "ja-JP"))

if let progress = kit.modelDownloadProgress {
    print("Downloading model: \(progress.fractionCompleted * 100)%")
}
```

You can use this progress to a `ProgressView` for visual feedback.

### Error Handling

AuralKit surfaces detailed `SpeechSessionError` values so you can present actionable messaging:

```swift
do {
    for try await segment in kit.startTranscribing() {
        // Use the transcription
    }
} catch let error as SpeechSessionError {
    switch error {
    case .modelDownloadNoInternet:
        // Prompt the user to reconnect before retrying
    case .modelDownloadFailed(let underlying):
        // Inspect `underlying` for more detail
    default:
        break
    }
} catch {
    // Handle unexpected errors
}
```

## API Reference

### SpeechSession

```swift
public final class SpeechSession: @unchecked Sendable {
    // Initialize with a locale
    public init(locale: Locale = .current)

    /// Current speech model download progress, if any
    public var modelDownloadProgress: Progress? { get }

    /// Start transcribing - returns stream of TranscriptionResult
    public func startTranscribing() -> AsyncThrowingStream<TranscriptionResult, Error>

    /// Stop transcribing
    public func stopTranscribing() async
}
```

### TranscriptionResult

```swift
public struct TranscriptionResult {
    /// The transcribed text with timing metadata
    public let text: AttributedString

    /// Whether this result is final or volatile (partial)
    public let isFinal: Bool
}
```

### Working with Results

Each `TranscriptionResult` contains an `AttributedString` with rich metadata:

```swift
for try await attributedText in session.startTranscribing() {
    // Get plain text
    let plainText = String(attributedText.characters)
    
    // Access timing information
    for run in attributedText.runs {
        if let audioRange = run.audioTimeRange {
            let startTime = audioRange.start.seconds
            let endTime = audioRange.end.seconds
            print("\(run.text): \(startTime)s - \(endTime)s")
        }
    }
}
```

## Permissions

Add to your `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access to transcribe speech.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>This app needs speech recognition to convert your speech to text.</string>
```

## Requirements

- iOS 26.0+ / macOS 26.0+
- Swift 6.2+
- Microphone and speech recognition permissions

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

AuralKit is available under the MIT License. See the [LICENSE](LICENSE) file for more info.
