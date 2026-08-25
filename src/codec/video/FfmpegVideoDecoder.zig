const FfmpegDemuxer = @import("../../demux/FfmpegDemuxer.zig");
const StreamInfo = @import("../../domain/StreamInfo.zig");
const c = @import("../../ffmpeg/bindings.zig").c;

ctx: *c.AVCodecContext,
stream_index: u32,

pub fn openFromDemuxer(demuxer: *const FfmpegDemuxer, stream: StreamInfo) !@This() {
    if (stream.kind != .video) return error.NotVideoStream;
    if (stream.index >= demuxer.streamCount()) return error.StreamNotFound;

    const av_stream = demuxer.format_ctx.streams[stream.index];
    const codecpar = av_stream.*.codecpar;
    const decoder = c.avcodec_find_decoder(codecpar.*.codec_id) orelse return error.DecoderNotFound;

    var ctx = c.avcodec_alloc_context3(decoder) orelse return error.OutOfMemory;
    errdefer c.avcodec_free_context(&ctx);

    if (c.avcodec_parameters_to_context(ctx, codecpar) < 0) {
        return error.Ffmpeg;
    }

    if (c.avcodec_open2(ctx, decoder, null) < 0) {
        return error.Ffmpeg;
    }

    return .{
        .ctx = ctx,
        .stream_index = stream.index,
    };
}

pub fn deinit(self: *@This()) void {
    var ctx: ?*c.AVCodecContext = self.ctx;
    c.avcodec_free_context(&ctx);
}
