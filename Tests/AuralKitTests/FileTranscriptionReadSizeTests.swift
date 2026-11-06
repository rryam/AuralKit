import Testing
@testable import AuralKit

@Suite("File transcription read sizes")
struct FileTranscriptionReadSizeTests {
    @Test("large file remainders fit a single buffer", arguments: [
        Int64(UInt32.max), Int64(UInt32.max) + 1, Int64.max
    ])
    func largeRemainders(_ remaining: Int64) {
        #expect(AudioFileReadSize.next(remaining: remaining, capacity: 4_096) == 4_096)
    }

    @Test("ordinary remainders include the final short read", arguments: [
        (Int64(0), UInt32(0)),
        (1, 1),
        (17, 17),
        (4_095, 4_095),
        (4_096, 4_096),
        (4_097, 4_096)
    ])
    func ordinaryRemainders(remaining: Int64, expected: UInt32) {
        #expect(AudioFileReadSize.next(remaining: remaining, capacity: 4_096) == expected)
    }

    @Test("the actual buffer capacity limits the read", arguments: [
        UInt32(0), 1, 17, 4_096, UInt32.max
    ])
    func capacityBoundaries(_ capacity: UInt32) {
        #expect(AudioFileReadSize.next(remaining: Int64.max, capacity: capacity) == capacity)
        #expect(AudioFileReadSize.next(remaining: 0, capacity: capacity) == 0)
        #expect(AudioFileReadSize.next(remaining: 1, capacity: capacity) == min(1, capacity))
    }

    @Test("nonpositive remainders produce no read", arguments: [Int64.min, -1, 0])
    func nonpositiveRemainders(_ remaining: Int64) {
        #expect(AudioFileReadSize.next(remaining: remaining, capacity: UInt32.max) == 0)
    }
}
