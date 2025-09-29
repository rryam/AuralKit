# AuralKit

[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2026%2B%20|%20macOS%2026%2B-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager)
[![GitHub release](https://img.shields.io/github/release/rryam/AuralKit.svg)](https://github.com/rryam/AuralKit/releases)
[![Codemagic build status](https://api.codemagic.io/apps/6858c0b3eab03a007ef8b1f6/auralkit/status_badge.svg)](https://codemagic.io/app/6858c0b3eab03a007ef8b1f6/auralkit/latest_build)

AuralKit is a simple, lightweight Swift wrapper for speech-to-text transcription using iOS 26's `SpeechTranscriber` and `SpeechAnalyzer` APIs while handling microphone capture, buffer conversion, model downloads, and cancellation on your behalf.

**Public API**: `SpeechSession` - A clean, session-based interface for speech transcription.

## Acknowledgements

This project would not have been possible without Apple's excellent sample code. The implementation is heavily inspired by [Bringing advanced speech-to-text capabilities to your app](https://developer.apple.com/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app), which shows how to add live speech-to-text transcription with `SpeechAnalyzer`.

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
                print("Final: \(result.text)")
            } else {
                print("Partial: \(result.text)")
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

### SwiftUI Example (Super Simple!)

```swift
import SwiftUI
import AuralKit

struct ContentView: View {
    @State private var session = SpeechSession()
    @State private var transcript: AttributedString = ""
    @State private var isTranscribing = false

    var body: some View {
        VStack(spacing: 20) {
            Text(transcript)
                .frame(minHeight: 100)
                .padding()

            Button(isTranscribing ? "Stop" : "Start") {
                if isTranscribing {
                    Task {
                        await session.stopTranscribing()
                        isTranscribing = false
                    }
                } else {
                    isTranscribing = true
                    Task {
                        for try await result in session.startTranscribing() {
                            if result.isFinal {
                                transcript += result.text
                            }
                        }
                        isTranscribing = false
                    }
                }
            }
        }
        .padding()
    }
}
```

### Partial Results

Add one more state variable to show real-time partial transcription:

```swift
struct ContentView: View {
    @State private var session = SpeechSession()
    @State private var finalText: AttributedString = ""
    @State private var partialText: AttributedString = ""
    @State private var isTranscribing = false

    var body: some View {
        VStack(spacing: 20) {
            Text(finalText + partialText)
                .frame(minHeight: 100)
                .padding()

            Button(isTranscribing ? "Stop" : "Start") {
                if isTranscribing {
                    Task {
                        await session.stopTranscribing()
                        isTranscribing = false
                    }
                } else {
                    isTranscribing = true
                    Task {
                        for try await result in session.startTranscribing() {
                            if result.isFinal {
                                finalText += result.text
                                partialText = ""
                            } else {
                                partialText = result.text
                            }
                        }
                        isTranscribing = false
                    }
                }
            }
        }
        .padding()
    }
}
```

The `TranscriptionManager` in the demo app adds language selection, history tracking, and export.

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
