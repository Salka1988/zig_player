pub const Codec = @import("Codec.zig").Codec;

pub const Kind = enum {
    video,
    audio,
    subtitle,
    other,
};

index: u32,
kind: Kind,
codec: Codec,
