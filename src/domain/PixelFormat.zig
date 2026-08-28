pub const PixelFormat = union(enum) {
    yuv420p,
    yuvj420p,
    yuv422p,
    nv12,
    other: i32,
};
