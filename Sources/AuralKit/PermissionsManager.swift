#if os(iOS)
import AVFoundation
#endif
import Speech

// MARK: - Permissions Manager

class PermissionsManager: @unchecked Sendable {

    /// Check if all required permissions are granted
    func isAuthorized() async -> Bool {
        // Check microphone permission
#if os(iOS)
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                return false
            }
        }
#endif

        // Check speech recognition permission
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }
}
