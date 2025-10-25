# Work Items

- [x] Add proper audio session teardown on cleanup so AVAudioSession is deactivated when transcription stops.
- [x] Handle AVAudioSession interruptions to pause and resume streaming reliably.
- [x] Support multi-subscriber AsyncStreams for status and audio-input updates.
- [x] Ensure the demo's VAD indicator restarts its task when toggling voice activation.
- [x] Add regression tests covering the new broadcast stream behavior.
