pub const Timestamp = @import("Timestamp.zig");
pub const AudioSampleFormat = @import("AudioSampleFormat.zig").AudioSampleFormat;

sample_count: u32,
sample_rate: u32,
channel_count: u32,
format: AudioSampleFormat,
pts: ?Timestamp,
