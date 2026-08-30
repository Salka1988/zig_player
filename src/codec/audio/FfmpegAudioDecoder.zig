const std = @import("std");

const AudioSampleFormat = @import("../../domain/AudioSampleFormat.zig").AudioSampleFormat;
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
converted_frame: ?*c.AVFrame = null,
swr_ctx: ?*c.SwrContext = null,
converted_source_format: c_int = -1,
converted_sample_rate: c_int = 0,
converted_channel_count: c_int = 0,
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
    if (self.swr_ctx) |ctx| {
        var ctx_to_free: ?*c.SwrContext = ctx;
        c.swr_free(&ctx_to_free);
    }

    if (self.converted_frame) |converted_frame| {
        var frame_to_free: ?*c.AVFrame = converted_frame;
        c.av_frame_free(&frame_to_free);
    }

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
        .format = sampleFormat(self.frame.format),
        .pts = self.timestamp(self.frame.best_effort_timestamp),
    };
}

pub fn currentF32Planar(self: *@This()) !F32PlanarAudioFrame {
    const frame = if (sampleFormat(self.frame.format) == .fltp)
        self.frame
    else
        try self.convertCurrentFrameToF32Planar();

    return self.f32PlanarFrame(frame);
}

fn f32PlanarFrame(self: *const @This(), frame: *const c.AVFrame) !F32PlanarAudioFrame {
    const channel_count: u32 = @intCast(frame.ch_layout.nb_channels);
    if (channel_count == 0 or channel_count > 2) {
        std.debug.print("unsupported audio channel count: {d}\n", .{channel_count});
        return error.UnsupportedAudioChannelCount;
    }

    var channels: [2][*c]const f32 = undefined;
    channels[0] = @ptrCast(@alignCast(frame.extended_data[0]));
    if (channel_count == 2) {
        channels[1] = @ptrCast(@alignCast(frame.extended_data[1]));
    } else {
        channels[1] = channels[0];
    }

    return .{
        .sample_count = @intCast(frame.nb_samples),
        .sample_rate = @intCast(frame.sample_rate),
        .channel_count = channel_count,
        .pts = self.timestamp(frame.best_effort_timestamp),
        .channels = channels,
    };
}

fn convertCurrentFrameToF32Planar(self: *@This()) !*c.AVFrame {
    var converted_frame = try self.conversionFrame();

    if (self.needsNewResampler()) {
        try self.configureResampler();
    }

    c.av_frame_unref(converted_frame);
    converted_frame.format = c.AV_SAMPLE_FMT_FLTP;
    converted_frame.sample_rate = self.frame.sample_rate;
    converted_frame.nb_samples = self.frame.nb_samples;
    try FfmpegError.check(c.av_channel_layout_copy(&converted_frame.ch_layout, &self.frame.ch_layout), "av_channel_layout_copy");
    try FfmpegError.check(c.av_frame_get_buffer(converted_frame, 0), "audio av_frame_get_buffer");

    const converted_samples = c.swr_convert_frame(self.swr_ctx, converted_frame, self.frame);
    try FfmpegError.check(converted_samples, "swr_convert_frame");

    converted_frame.best_effort_timestamp = self.frame.best_effort_timestamp;
    return converted_frame;
}

fn needsNewResampler(self: *const @This()) bool {
    return self.swr_ctx == null or
        self.converted_source_format != self.frame.format or
        self.converted_sample_rate != self.frame.sample_rate or
        self.converted_channel_count != self.frame.ch_layout.nb_channels;
}

fn configureResampler(self: *@This()) !void {
    var swr_ctx = self.swr_ctx;
    try FfmpegError.check(
        c.swr_alloc_set_opts2(
            &swr_ctx,
            &self.frame.ch_layout,
            c.AV_SAMPLE_FMT_FLTP,
            self.frame.sample_rate,
            &self.frame.ch_layout,
            self.frame.format,
            self.frame.sample_rate,
            0,
            null,
        ),
        "swr_alloc_set_opts2",
    );
    self.swr_ctx = swr_ctx;
    try FfmpegError.check(c.swr_init(self.swr_ctx), "swr_init");

    self.converted_source_format = self.frame.format;
    self.converted_sample_rate = self.frame.sample_rate;
    self.converted_channel_count = self.frame.ch_layout.nb_channels;
}

fn conversionFrame(self: *@This()) !*c.AVFrame {
    if (self.converted_frame) |frame| return frame;

    const frame = c.av_frame_alloc() orelse return error.OutOfMemory;
    self.converted_frame = frame;
    return frame;
}

fn timestamp(self: *const @This(), value: i64) ?AudioFrame.Timestamp {
    return if (value == c.AV_NOPTS_VALUE)
        null
    else
        .{ .seconds = self.time_base.seconds(value) };
}

fn sampleFormat(format: c_int) AudioSampleFormat {
    return switch (format) {
        c.AV_SAMPLE_FMT_FLTP => .fltp,
        else => .{ .other = format },
    };
}
