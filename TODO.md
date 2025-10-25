# Work Items

- [x] Add proper audio session teardown on cleanup so AVAudioSession is deactivated when transcription stops.
- [x] Handle AVAudioSession interruptions to pause and resume streaming reliably.
- [ ] Support multi-subscriber AsyncStreams for status and audio-input updates.
- [ ] Ensure the demo's VAD indicator restarts its task when toggling voice activation.
- [ ] Add regression tests covering the new broadcast stream behavior.
