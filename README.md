# AuralKit

![Swift](https://img.shields.io/badge/Swift-6.2+-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2026%2B%20|%20macOS%2026%2B-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)
[![GitHub release](https://img.shields.io/github/release/rryam/AuralKit.svg)](https://github.com/rryam/AuralKit/releases)

A simple, lightweight Swift wrapper for speech-to-text transcription using Apple's Speech APIs.

## Features

- **Simple async/await API** for speech transcription
- **AttributedString output** with audio timing metadata
- **Multi-language support** with automatic model downloading
- **Native Apple types** - no custom wrappers
- **Privacy-focused** - on-device processing

## Overview

AuralKit provides a clean, minimal API for adding speech transcription to your app using iOS 26's `SpeechTranscriber` and `SpeechAnalyzer` APIs.

## Quick Start

```swift
import AuralKit

// Create an instance with your preferred locale
let auralKit = AuralKit(locale: .current)

// Start transcribing
for try await text in auralKit.startTranscribing() {
    print(text)  // AttributedString with timing metadata
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
    .package(url: "https://github.com/rryam/AuralKit", from: "0.1.0")
]
```

## Usage

### Simple Transcription

```swift
import AuralKit

// Create with default locale
let auralKit = AuralKit()

// Or specify a locale
let auralKit = AuralKit(locale: Locale(identifier: "es-ES"))

// Start transcribing
for try await attributedText in auralKit.startTranscribing() {
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

// Stop when needed
await auralKit.stopTranscribing()
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
                await auralKit.stopTranscribing()
                isTranscribing = false
            }
        } else {
            isTranscribing = true
            Task {
                do {
                    for try await attributedText in auralKit.startTranscribing() {
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

## API Reference

### AuralKit

```swift
@available(iOS 26.0, macOS 26.0, *)
public final class AuralKit: @unchecked Sendable {
    // Initialize with a locale
    public init(locale: Locale = .current)

    // Start transcribing
    public func startTranscribing() -> AsyncThrowingStream<AttributedString, Error>

    // Stop transcribing
    public func stopTranscribing() async
}
```

### AttributedString Output

The transcription returns an `AttributedString` with rich metadata:

```swift
for try await attributedText in auralKit.startTranscribing() {
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

### Supported Locales

AuralKit supports all locales available through `SpeechTranscriber.supportedLocales`. Common examples:

- `Locale(identifier: "en-US")` - English (United States)
- `Locale(identifier: "es-ES")` - Spanish (Spain)
- `Locale(identifier: "fr-FR")` - French (France)
- `Locale(identifier: "de-DE")` - German (Germany)
- `Locale(identifier: "it-IT")` - Italian (Italy)
- `Locale(identifier: "pt-BR")` - Portuguese (Brazil)
- `Locale(identifier: "zh-CN")` - Chinese (Simplified)
- `Locale(identifier: "ja-JP")` - Japanese (Japan)
- `Locale(identifier: "ko-KR")` - Korean (Korea)

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

## Error Handling

AuralKit provides detailed, localized error messages for all error conditions:

```swift
do {
    for try await text in auralKit.startTranscribing() {
        print(text)
    }
} catch {
    // AuralKitError provides localized descriptions, failure reasons, and recovery suggestions
    if let auralKitError = error as? AuralKitError {
        print("Error: \(auralKitError.localizedDescription)")
        if let failureReason = auralKitError.failureReason {
            print("Reason: \(failureReason)")
        }
        if let recoverySuggestion = auralKitError.recoverySuggestion {
            print("Suggestion: \(recoverySuggestion)")
        }
    } else {
        print("Unexpected error: \(error)")
    }
}
```

### Error Types

- `microphonePermissionDenied` - Microphone access not granted
- `speechRecognitionPermissionDenied` - Speech recognition access not granted
- `unsupportedLocale(Locale)` - Selected language not supported
- `recognitionStreamSetupFailed` - Failed to initialize speech recognition
- `invalidAudioDataType` - Audio format incompatible
- `bufferConverterCreationFailed` - Audio processing setup failed
- `conversionBufferCreationFailed` - Audio buffer allocation failed
- `audioConversionFailed(NSError?)` - Audio format conversion failed

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

AuralKit is available under the MIT License. See the [LICENSE](LICENSE) file for more info.