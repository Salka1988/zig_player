/// Compressed packet bytes. Ownership depends on the producer.
data: []const u8,
stream_index: u32,
pts: ?i64 = null,
dts: ?i64 = null,
