pub const Timestamp = @import("Timestamp.zig");
pub const PixelFormat = @import("PixelFormat.zig").PixelFormat;

width: u32,
height: u32,
format: PixelFormat,
pts: ?Timestamp,
