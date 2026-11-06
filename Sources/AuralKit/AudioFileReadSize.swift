/// Bounds the signed 64-bit file remainder before narrowing to a per-read count.
/// Even a file longer than UInt32.max frames needs only one buffer per read.
enum AudioFileReadSize {
    static func next(remaining: Int64, capacity: UInt32) -> UInt32 {
        UInt32(min(max(remaining, 0), Int64(capacity)))
    }
}
