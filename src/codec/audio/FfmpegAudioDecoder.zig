const FfmpegDemuxer = @import("../../demux/FfmpegDemuxer.zig");
const AudioFrame = @import("../../domain/AudioFrame.zig");
const StreamInfo = @import("../../domain/StreamInfo.zig");
const TimeBase = @import("../../domain/TimeBase.zig");
const c = @import("../../ffmpeg/bindings.zig").c;

ctx: *c.AVCodecContext,
frame: *c.AVFrame,
stream_index: u32,
time_base: TimeBase,

pub fn openFromDemuxer(demuxer: *const FfmpegDemuxer, stream: StreamInfo) !@This() {
    if (stream.kind != .audio) return error.NotAudioStream;
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

    const frame = c.av_frame_alloc() orelse return error.OutOfMemory;
    errdefer {
        var frame_to_free: ?*c.AVFrame = frame;
        c.av_frame_free(&frame_to_free);
    }

    return .{
        .ctx = ctx,
        .frame = frame,
        .stream_index = stream.index,
        .time_base = stream.time_base,
    };
}

pub fn deinit(self: *@This()) void {
    var frame: ?*c.AVFrame = self.frame;
    c.av_frame_free(&frame);

    var ctx: ?*c.AVCodecContext = self.ctx;
    c.avcodec_free_context(&ctx);
}

pub fn sendCurrentPacket(self: *@This(), demuxer: *const FfmpegDemuxer) !void {
    if (demuxer.packet.stream_index != self.stream_index) return error.WrongStream;

    const result = c.avcodec_send_packet(self.ctx, demuxer.packet);
    if (result < 0) return error.Ffmpeg;
}

pub fn sendEndOfStream(self: *@This()) !void {
    const result = c.avcodec_send_packet(self.ctx, null);
    if (result < 0) return error.Ffmpeg;
}

pub fn receive(self: *@This()) !?AudioFrame {
    const result = c.avcodec_receive_frame(self.ctx, self.frame);
    if (result == c.AVERROR(c.EAGAIN) or result == c.AVERROR_EOF) return null;
    if (result < 0) return error.Ffmpeg;

    return .{
        .sample_count = @intCast(self.frame.nb_samples),
        .sample_rate = @intCast(self.frame.sample_rate),
        .channel_count = @intCast(self.frame.ch_layout.nb_channels),
        .pts = self.timestamp(self.frame.best_effort_timestamp),
    };
}

fn timestamp(self: *const @This(), value: i64) ?AudioFrame.Timestamp {
    return if (value == c.AV_NOPTS_VALUE)
        null
    else
        .{ .seconds = self.time_base.seconds(value) };
}
