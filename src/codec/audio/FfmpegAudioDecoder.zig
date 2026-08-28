const std = @import("std");

const FfmpegError = @import("../../ffmpeg/Error.zig");
const FfmpegDemuxer = @import("../../demux/FfmpegDemuxer.zig");
const AudioFrame = @import("../../domain/AudioFrame.zig");
const F32PlanarAudioFrame = @import("../../domain/F32PlanarAudioFrame.zig");
const Packet = @import("../../ffmpeg/Packet.zig");
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

    try FfmpegError.check(c.avcodec_parameters_to_context(ctx, codecpar), "audio avcodec_parameters_to_context");

    try FfmpegError.check(c.avcodec_open2(ctx, decoder, null), "audio avcodec_open2");

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
    try FfmpegError.check(result, "audio avcodec_send_packet");
}

pub fn sendPacket(self: *@This(), packet: *const Packet) !void {
    if (packet.streamIndex() != self.stream_index) return error.WrongStream;

    const result = c.avcodec_send_packet(self.ctx, packet.packet);
    try FfmpegError.check(result, "audio avcodec_send_packet");
}

pub fn sendEndOfStream(self: *@This()) !void {
    const result = c.avcodec_send_packet(self.ctx, null);
    try FfmpegError.check(result, "audio avcodec_send_packet_eof");
}

pub fn receive(self: *@This()) !?AudioFrame {
    const result = c.avcodec_receive_frame(self.ctx, self.frame);
    if (result == c.AVERROR(c.EAGAIN) or result == c.AVERROR_EOF) return null;
    try FfmpegError.check(result, "audio avcodec_receive_frame");

    return .{
        .sample_count = @intCast(self.frame.nb_samples),
        .sample_rate = @intCast(self.frame.sample_rate),
        .channel_count = @intCast(self.frame.ch_layout.nb_channels),
        .pts = self.timestamp(self.frame.best_effort_timestamp),
    };
}

pub fn currentF32Planar(self: *const @This()) !F32PlanarAudioFrame {
    if (self.frame.format != c.AV_SAMPLE_FMT_FLTP) {
        std.debug.print("unsupported audio sample format: {d}\n", .{self.frame.format});
        return error.UnsupportedAudioSampleFormat;
    }

    const channel_count: u32 = @intCast(self.frame.ch_layout.nb_channels);
    if (channel_count == 0 or channel_count > 2) {
        std.debug.print("unsupported audio channel count: {d}\n", .{channel_count});
        return error.UnsupportedAudioChannelCount;
    }

    var channels: [2][*c]const f32 = undefined;
    channels[0] = @ptrCast(@alignCast(self.frame.extended_data[0]));
    if (channel_count == 2) {
        channels[1] = @ptrCast(@alignCast(self.frame.extended_data[1]));
    } else {
        channels[1] = channels[0];
    }

    return .{
        .sample_count = @intCast(self.frame.nb_samples),
        .sample_rate = @intCast(self.frame.sample_rate),
        .channel_count = channel_count,
        .pts = self.timestamp(self.frame.best_effort_timestamp),
        .channels = channels,
    };
}

fn timestamp(self: *const @This(), value: i64) ?AudioFrame.Timestamp {
    return if (value == c.AV_NOPTS_VALUE)
        null
    else
        .{ .seconds = self.time_base.seconds(value) };
}
