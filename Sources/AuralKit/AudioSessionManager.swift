#if os(iOS)
import AVFoundation

// MARK: - Audio Session Manager

class AudioSessionManager: @unchecked Sendable {

    /// Set up the audio session for recording
    func setUpAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .spokenAudio)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }
}
#endif
