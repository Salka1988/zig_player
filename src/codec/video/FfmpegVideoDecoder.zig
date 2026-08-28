const std = @import("std");

const FfmpegError = @import("../../ffmpeg/Error.zig");
const FfmpegDemuxer = @import("../../demux/FfmpegDemuxer.zig");
const Packet = @import("../../ffmpeg/Packet.zig");
const StreamInfo = @import("../../domain/StreamInfo.zig");
const TimeBase = @import("../../domain/TimeBase.zig");
const VideoFrame = @import("../../domain/VideoFrame.zig");
const Yuv420pFrame = @import("../../domain/Yuv420pFrame.zig");
const c = @import("../../ffmpeg/bindings.zig").c;

ctx: *c.AVCodecContext,
frame: *c.AVFrame,
converted_frame: ?*c.AVFrame = null,
sws_ctx: ?*c.SwsContext = null,
converted_source_format: c_int = -1,
stream_index: u32,
time_base: TimeBase,

pub fn openFromDemuxer(demuxer: *const FfmpegDemuxer, stream: StreamInfo) !@This() {
    if (stream.kind != .video) return error.NotVideoStream;
    if (stream.index >= demuxer.streamCount()) return error.StreamNotFound;

    const av_stream = demuxer.format_ctx.streams[stream.index];
    const codecpar = av_stream.*.codecpar;
    const decoder = c.avcodec_find_decoder(codecpar.*.codec_id) orelse return error.DecoderNotFound;

    var ctx = c.avcodec_alloc_context3(decoder) orelse return error.OutOfMemory;
    errdefer c.avcodec_free_context(&ctx);

    try FfmpegError.check(c.avcodec_parameters_to_context(ctx, codecpar), "video avcodec_parameters_to_context");

    try FfmpegError.check(c.avcodec_open2(ctx, decoder, null), "video avcodec_open2");

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
    if (self.sws_ctx) |ctx| {
        c.sws_freeContext(ctx);
    }

    if (self.converted_frame) |frame| {
        var frame_to_free: ?*c.AVFrame = frame;
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
    try FfmpegError.check(result, "video avcodec_send_packet");
}

pub fn sendPacket(self: *@This(), packet: *const Packet) !void {
    if (packet.streamIndex() != self.stream_index) return error.WrongStream;

    const result = c.avcodec_send_packet(self.ctx, packet.packet);
    try FfmpegError.check(result, "video avcodec_send_packet");
}

pub fn sendEndOfStream(self: *@This()) !void {
    const result = c.avcodec_send_packet(self.ctx, null);
    try FfmpegError.check(result, "video avcodec_send_packet_eof");
}

pub fn receive(self: *@This()) !?VideoFrame {
    const result = c.avcodec_receive_frame(self.ctx, self.frame);
    if (result == c.AVERROR(c.EAGAIN) or result == c.AVERROR_EOF) return null;
    try FfmpegError.check(result, "video avcodec_receive_frame");

    return .{
        .width = @intCast(self.frame.width),
        .height = @intCast(self.frame.height),
        .pts = self.timestamp(self.frame.best_effort_timestamp),
    };
}

pub fn currentYuv420p(self: *@This()) !Yuv420pFrame {
    if (isYuv420pFrame(self.frame)) return yuv420pFrame(self.frame);

    const converted = try self.convertCurrentFrameToYuv420p();
    return yuv420pFrame(converted);
}

fn timestamp(self: *const @This(), value: i64) ?VideoFrame.Timestamp {
    return if (value == c.AV_NOPTS_VALUE)
        null
    else
        .{ .seconds = self.time_base.seconds(value) };
}

fn isYuv420pFrame(frame: *const c.AVFrame) bool {
    return frame.format == c.AV_PIX_FMT_YUV420P or frame.format == c.AV_PIX_FMT_YUVJ420P;
}

fn yuv420pFrame(frame: *const c.AVFrame) Yuv420pFrame {
    return .{
        .width = @intCast(frame.width),
        .height = @intCast(frame.height),
        .y = frame.data[0],
        .u = frame.data[1],
        .v = frame.data[2],
        .y_stride = frame.linesize[0],
        .u_stride = frame.linesize[1],
        .v_stride = frame.linesize[2],
    };
}

fn convertCurrentFrameToYuv420p(self: *@This()) !*c.AVFrame {
    const source_format = self.frame.format;
    const converted = try self.conversionFrame();

    if (self.sws_ctx == null or self.converted_source_format != source_format) {
        if (self.sws_ctx) |ctx| c.sws_freeContext(ctx);
        self.sws_ctx = c.sws_getContext(
            self.frame.width,
            self.frame.height,
            source_format,
            self.frame.width,
            self.frame.height,
            c.AV_PIX_FMT_YUV420P,
            c.SWS_BILINEAR,
            null,
            null,
            null,
        ) orelse {
            std.debug.print("unsupported pixel format: {d}\n", .{source_format});
            return error.UnsupportedPixelFormat;
        };
        self.converted_source_format = source_format;
    }

    try FfmpegError.check(c.av_frame_make_writable(converted), "av_frame_make_writable");
    const height = c.sws_scale(
        self.sws_ctx.?,
        @ptrCast(&self.frame.data),
        @ptrCast(&self.frame.linesize),
        0,
        self.frame.height,
        @ptrCast(&converted.data),
        @ptrCast(&converted.linesize),
    );
    if (height != self.frame.height) {
        std.debug.print("ffmpeg error: sws_scale result={d}\n", .{height});
        return error.Ffmpeg;
    }

    return converted;
}

fn conversionFrame(self: *@This()) !*c.AVFrame {
    if (self.converted_frame) |frame| {
        if (frame.width == self.frame.width and frame.height == self.frame.height) return frame;

        if (self.sws_ctx) |ctx| c.sws_freeContext(ctx);
        self.sws_ctx = null;
        self.converted_source_format = -1;

        var frame_to_free: ?*c.AVFrame = frame;
        c.av_frame_free(&frame_to_free);
        self.converted_frame = null;
    }

    const frame = c.av_frame_alloc() orelse return error.OutOfMemory;
    errdefer {
        var frame_to_free: ?*c.AVFrame = frame;
        c.av_frame_free(&frame_to_free);
    }

    frame.*.format = c.AV_PIX_FMT_YUV420P;
    frame.*.width = self.frame.width;
    frame.*.height = self.frame.height;
    try FfmpegError.check(c.av_frame_get_buffer(frame, 32), "av_frame_get_buffer");

    self.converted_frame = frame;
    return frame;
}
