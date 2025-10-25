# AuralKit

[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2026%2B%20|%20macOS%2026%2B-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager)
[![GitHub release](https://img.shields.io/github/release/rryam/AuralKit.svg)](https://github.com/rryam/AuralKit/releases)
[![Codemagic build status](https://api.codemagic.io/apps/6858c0b3eab03a007ef8b1f6/auralkit/status_badge.svg)](https://codemagic.io/app/6858c0b3eab03a007ef8b1f6/auralkit/latest_build)

AuralKit is a simple, lightweight Swift wrapper for speech-to-text transcription using iOS 26's `SpeechTranscriber` and `SpeechAnalyzer` APIs while handling microphone capture, buffer conversion, model downloads, and cancellation on your behalf.

**Public API**: `SpeechSession` - A clean, session-based interface for speech transcription.

## Features

- End-to-end streaming pipeline built on `SpeechTranscriber` and `SpeechAnalyzer`
- Automatic locale model installation with progress reporting
- Configurable voice activation (VAD) with optional detector result streaming
- Audio input monitoring for device route changes on iOS and macOS
- Async streams for lifecycle status, audio inputs, and transcription results
- Device capability helper to inspect available transcribers and locales
- SwiftUI-friendly API that mirrors Apple's sample project design

## Table of Contents

- [Features](#features)
- [Acknowledgements](#acknowledgements)
- [Quick Start](#quick-start)
- [Installation](#installation)
  - [Swift Package Manager](#swift-package-manager)
- [Usage](#usage)
  - [Simple Transcription](#simple-transcription)
  - [Partial Results](#partial-results)
- [Session Observability](#session-observability)
  - [Monitoring Model Downloads](#monitoring-model-downloads)
  - [Status Updates](#status-updates)
  - [Tracking Audio Input Changes](#tracking-audio-input-changes)
  - [Voice Activation (VAD)](#voice-activation-vad)
  - [Device Capabilities](#device-capabilities)
- [Demo App](#demo-app)
- [Architecture Overview](#architecture-overview)
- [API Reference](#api-reference)
- [Permissions](#permissions)
- [Requirements](#requirements)
- [Contributing](#contributing)
- [License](#license)

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
        let stream = session.startTranscribing()
        for try await result in stream {
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
    .package(url: "https://github.com/rryam/AuralKit", from: "1.4.0")
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
        let stream = session.startTranscribing()
        for try await result in stream {
            let attributedText = result.text

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
    @State private var status: SpeechSession.Status = .idle

    var body: some View {
        VStack(spacing: 20) {
            Text(transcript)
                .frame(minHeight: 100)
                .padding()

            Button(status == .transcribing ? "Pause" : "Start") {
                Task {
                    switch status {
                    case .idle:
                        transcript = ""
                        for try await result in session.startTranscribing() {
                            if result.isFinal {
                                transcript += result.text
                            }
                        }
                    case .transcribing:
                        await session.pauseTranscribing()
                    case .paused:
                        try? await session.resumeTranscribing()
                    default:
                        break
                    }
                }
            }
        }
        .task {
            for await newStatus in session.statusStream {
                status = newStatus
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
    @State private var status: SpeechSession.Status = .idle

    var body: some View {
        VStack(spacing: 20) {
            Text(finalText + partialText)
                .frame(minHeight: 100)
                .padding()

            Button(statusButtonTitle) {
                Task {
                    switch status {
                    case .idle:
                        finalText = ""
                        partialText = ""
                        for try await result in session.startTranscribing() {
                            if result.isFinal {
                                finalText += result.text
                                partialText = ""
                            } else {
                                partialText = result.text
                            }
                        }
                    case .transcribing:
                        await session.pauseTranscribing()
                    case .paused:
                        try? await session.resumeTranscribing()
                    default:
                        break
                    }
                }
            }
        }
        .task {
            for await newStatus in session.statusStream {
                status = newStatus
            }
        }
        .padding()
    }

    private var statusButtonTitle: String {
        switch status {
        case .idle:
            return "Start"
        case .transcribing:
            return "Pause"
        case .paused:
            return "Resume"
        default:
            return "Working…"
        }
    }
}
```

The `TranscriptionManager` in the demo app adds language selection, history tracking, and export.

### Error Handling

AuralKit surfaces detailed `SpeechSessionError` values so you can present actionable messaging:

```swift
do {
    let stream = await kit.startTranscribing()
    for try await segment in stream {
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

## Session Observability

### Monitoring Model Downloads

When a locale has not been installed yet, AuralKit automatically downloads the appropriate speech model. You can observe download progress through the `modelDownloadProgress` property:

```swift
let session = SpeechSession(locale: Locale(identifier: "ja-JP"))

if let progress = await session.modelDownloadProgress {
    print("Downloading model: \(progress.fractionCompleted * 100)%")
}
```

Bind this progress to a `ProgressView` or custom HUD to keep users informed during large downloads.

### Status Updates

Lifecycle state changes flow through `statusStream`, making it easy to mirror session status in UI:

```swift
let session = SpeechSession()

Task {
    for await status in session.statusStream {
        print("Session status:", status)
    }
}
```

The `status` property always holds the most recent value—for example, `status == .paused` when the pipeline is temporarily halted.

### Tracking Audio Input Changes

On iOS and macOS, subscribe to `audioInputConfigurationStream` to react whenever the active microphone changes (e.g., headphones connected/disconnected):

```swift
Task {
    for await info in session.audioInputConfigurationStream {
        guard let info else { continue }
        print("Active input:", info.portName)
    }
}
```

Use the emitted metadata to refresh UI or reconfigure audio routing when needed.

### Voice Activation (VAD)

Voice activation uses Apple’s on-device Voice Activity Detection (VAD) to pause the analyzer during silence, saving power in long-running sessions:

```swift
let session = SpeechSession()
session.configureVoiceActivation(
    detectionOptions: .init(sensitivityLevel: .medium),
    reportResults: true
)

Task {
    if let detectorStream = session.speechDetectorResultsStream {
        for await detection in detectorStream {
            print("Speech detected:", detection.speechDetected)
        }
    }
}

for try await result in session.startTranscribing() {
    // Handle results
}
```

- Tune `detectionOptions.sensitivityLevel` (`.low`, `.medium`, `.high`) to balance accuracy and power savings.
- When `reportResults` is `false`, AuralKit still skips silence but keeps the detector stream `nil`.
- Inspect `isSpeechDetected` for the most recent detector state, or call `disableVoiceActivation()` to revert to continuous transcription.

> **Requirements:** Voice activation is available on platforms where `SpeechDetector` conforms to `SpeechModule`.

### Device Capabilities

Check the active device’s recognition support up front so you can tailor UI and feature availability:

```swift
let capabilities = await SpeechSession.deviceCapabilities()

if capabilities.supportsDictationTranscriber {
    // Offer a dictation-optimized mode when supported.
}

let supportedIdentifiers = capabilities.supportedLocales.map { $0.identifier(.bcp47) }
print("Supports up to \(capabilities.maxReservedLocales) reserved locales: \(supportedIdentifiers)")

let dictationIdentifiers = capabilities.supportedDictationLocales.map { $0.identifier(.bcp47) }
print("Dictation transcriber supports: \(dictationIdentifiers)")
```

Use the returned metadata to populate locale pickers, display download guidance, or gracefully disable transcription when models are unavailable.

## Architecture Overview

- **SpeechSession** – Main entry point exposed to apps; coordinates permission checks, audio engine lifecycle, and async streams.
- **SpeechSession+Pipeline** – Handles permissions, audio session activation, stream wiring, and orderly teardown of the pipeline.
- **SpeechSession+Transcriber** – Builds the analyzer graph, installs optional modules like `SpeechDetector`, and feeds audio buffers into the analyzer.
- **ModelManager** – Ensures locale models and supplemental assets are present, tracks download progress, and releases reserved locales on teardown.
- **BufferConverter** – Mirrors Apple’s sample to convert tap buffers into analyzer-compatible `AVAudioPCMBuffer`s without blocking real-time threads.
- **SpeechDetector Integration** – Opt-in module that provides VAD power savings and optional detection result streaming on supported OS releases.

## API Reference

### SpeechSession

```swift
public actor SpeechSession {
    // Initialize with a locale
    public init(locale: Locale = .current)

    /// Current speech model download progress, if any
    public var modelDownloadProgress: Progress? { get }

    /// Start transcribing - returns stream of SpeechTranscriber.Result
    public func startTranscribing() async -> AsyncThrowingStream<SpeechTranscriber.Result, Error>

    /// Stop transcribing
    public func stopTranscribing() async
}
```

### Result Type

AuralKit returns `SpeechTranscriber.Result` directly from the Speech framework, which provides:

```swift
public struct Result {
    /// The most likely transcription with timing and confidence metadata
    public var text: AttributedString
    
    /// Alternative interpretations in descending order of likelihood
    public let alternatives: [AttributedString]
    
    /// Whether this result is final or volatile (partial)
    public var isFinal: Bool
    
    /// The audio time range this result applies to
    public let range: CMTimeRange
    
    /// Time up to which results are finalized
    public let resultsFinalizationTime: CMTime
}
```

### Working with Results

Access transcription text, timing, confidence scores, and alternatives:

```swift
let stream = session.startTranscribing()
for try await result in stream {
    // Get plain text
    let plainText = String(result.text.characters)
    
    // Access timing information
    for run in result.text.runs {
        if let audioRange = run.audioTimeRange {
            let startTime = audioRange.start.seconds
            let endTime = audioRange.end.seconds
            print("\(run.text): \(startTime)s - \(endTime)s")
        }
        
        // Access confidence scores (0.0 to 1.0)
        if let confidence = run.transcriptionConfidence {
            print("Confidence: \(confidence)")
        }
    }
    
    // Access alternative transcriptions
    for (index, alternative) in result.alternatives.enumerated() {
        print("Alternative \(index): \(String(alternative.characters))")
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
