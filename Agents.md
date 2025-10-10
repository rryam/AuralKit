# Agents.md

Guidance for AI coding agents (and future contributors) working in this repository.

Use this document as the single source of truth when you need contextual project
information, preferred conventions, and required safety checks. It merges and replaces
the previous `CLAUDE.md` guidance.

---

## Project Snapshot

- **Name**: AuralKit (Swift Package)
- **Platforms**: iOS 26+, macOS 26+
- **Primary API**: `SpeechSession` (actor living in `Sources/AuralKit/SpeechSession.swift`)
- **Purpose**: Real‑time speech‑to‑text using Apple’s `SpeechTranscriber` / `SpeechAnalyzer`
- **Demo App**: SwiftUI app in the `Aural/` directory (scheme `Aural`)

---

## Design Principles

1. **Package vs. API Name**  
   Keep the package name `AuralKit`. The public API a client uses is the `SpeechSession`
   actor—do not rename the package or folders to match the API.

2. **AttributedString Pipeline**  
   All transcription text travels as `AttributedString` so `.audioTimeRange` metadata
   survives. Convert to `String` only for UI affordances (e.g. `ShareLink`).

3. **Match Apple’s Reference Implementation**  
   Buffer conversion, analyzer setup, and result handling mirror Apple’s SpeechExample.
   When touching those paths, compare against the reference before changing anything.

4. **Session-Based Simplicity**  
   The API should remain usable in ~30 lines of SwiftUI. No required manager layer.
   Optional helpers (like the demo’s `TranscriptionManager`) must stay opt-in.

5. **Cross-Platform Correctness**  
   iOS uses `AVAudioSession` while macOS focuses on Core Audio + `AVAudioEngine`
   configuration changes. Platform checks (`#if os(iOS)`, `#if os(macOS)`) are critical.

---

## Key Directories

| Path                      | Purpose |
|---------------------------|---------|
| `Sources/AuralKit/`       | Package source. `SpeechSession.swift` is the public API. |
| `Sources/AuralKit/AudioInputInfo.swift` | Shared audio-input metadata helpers (iOS + macOS). |
| `Aural/`                  | Demo SwiftUI app showing minimal and advanced flows. |
| `Tests/AuralKitTests/`    | Minimal smoke tests (logic-heavy testing requires real devices). |

---

## Build & Test Commands

```bash
# Package builds
swift build           # primary build
swift test            # run package tests

# Demo app (macOS destination)
xcodebuild -scheme Aural -project Aural.xcodeproj -destination 'platform=macOS' build

# Demo app (iOS Simulator)
xcodebuild -scheme Aural -project Aural.xcodeproj \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

> **Tip**: Simulator builds ensure the latest Swift 6 concurrency rules are satisfied.
> Physical hardware is still required to validate live audio capture.

---

## Implementation Notes

### Result Handling Contract

```swift
for try await result in session.startTranscribing() {
    if result.isFinal {
        finalizedText += result.text   // append final results
        partialText = ""
    } else {
        partialText = result.text      // replace volatile text
    }
}
```

- Do not infer result type from styling—always use `result.isFinal`.
- Final text is cumulative; volatile text represents the most recent partial string.

### Audio Buffer Conversion

`BufferConverter.swift` is copied from Apple’s sample and must remain byte-for-byte,
including `converter.primeMethod = .none`. Ask for explicit approval before editing.

### Audio Input Monitoring

- iOS: listen to `AVAudioSession.routeChangeNotification`, then reset the engine if the
  input port actually changes. Publish fresh metadata through `AudioInputInfo`.
- macOS: rely on `AVAudioEngineConfigurationChange` notifications and query Core Audio
  for the default input (`AudioInputInfo.current()`).

### Concurrency

- `SpeechSession` is an `@unchecked Sendable` actor; respect isolation.
- When bridging notifications into `Task`, capture only the data you need and, if
  touching UI- or engine-bound state, hop onto `@MainActor`.
- Avoid sharing mutable state between tasks without actor or `Sendable` guarantees.

### Testing Framework

- All tests must use Swift Testing (`import Testing`). Avoid introducing new XCTest-based suites.

---

## Contribution Checklist

Before opening a PR (or completing an automated change):

- [ ] Swift build succeeds locally (`swift build` and `swift test`).
- [ ] Demo app builds for both macOS and an iOS Simulator target if relevant code changes.
- [ ] Route-change handling remains platform-aware (`#if os(iOS)` vs `#if os(macOS)`).
- [ ] `AttributedString` usage is preserved throughout the speech pipeline.
- [ ] `BufferConverter` remains untouched unless explicitly approved.
- [ ] Documentation updated when public API or workflows change (`README`, this file, etc.).
- [ ] No stray instruction files (`CLAUDE.md`, `AGENTS.md`, etc.)—this document supersedes them.

---

## Working With Documentation

- Keep instructions concise but complete; link or reference Apple docs when helpful.
- If you extend this guide, add to the relevant section instead of creating a new file.
- When updating onboarding information, ensure both the package README and this agents
  guide stay in sync.

---

## Quick Reference

- Minimal transcription example lives in `Aural/MinimalTranscriptionView.swift`.
- Advanced transcription UI lives in `Aural/TranscriptionView.swift`.
- Error cases and localized descriptions are centralized in `Sources/AuralKit/SpeechSessionError.swift`.
- CI uses Codemagic (`codemagic.yaml`); green builds are required before merging.

Happy transcribing!

