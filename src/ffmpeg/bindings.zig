pub const c = @cImport({
    @cInclude("libavformat/avformat.h");
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libavutil/avutil.h");
    @cInclude("libswscale/swscale.h");
    @cInclude("libswresample/swresample.h");
});

test "ffmpeg version is available" {
    _ = c.avformat_version();
}
