pub const Codec = @import("Codec.zig").Codec;
const TimeBase = @import("TimeBase.zig");

pub const Kind = enum {
    video,
    audio,
    subtitle,
    other,
};

index: u32,
kind: Kind,
codec: Codec,
time_base: TimeBase,
