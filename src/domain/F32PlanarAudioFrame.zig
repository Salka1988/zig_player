pub const Timestamp = @import("Timestamp.zig");

sample_count: u32,
sample_rate: u32,
channel_count: u32,
pts: ?Timestamp,
channels: [2][*c]const f32,
