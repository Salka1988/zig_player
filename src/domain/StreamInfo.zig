pub const Kind = enum {
    video,
    audio,
    subtitle,
    other,
};

index: u32,
kind: Kind,
codec_id: u32,
