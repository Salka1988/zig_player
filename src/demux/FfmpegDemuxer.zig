const std = @import("std");

const Packet = @import("../domain/Packet.zig");
const StreamInfo = @import("../domain/StreamInfo.zig");
const c = @import("../ffmpeg/bindings.zig").c;

format_ctx: *c.AVFormatContext,
packet: *c.AVPacket,

pub fn open(allocator: std.mem.Allocator, path: []const u8) !@This() {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    var format_ctx: ?*c.AVFormatContext = null;
    if (c.avformat_open_input(&format_ctx, path_z.ptr, null, null) < 0) {
        return error.Ffmpeg;
    }
    errdefer if (format_ctx != null) {
        c.avformat_close_input(&format_ctx);
    };

    if (c.avformat_find_stream_info(format_ctx, null) < 0) {
        return error.Ffmpeg;
    }

    return .{
        .format_ctx = format_ctx.?,
        .packet = c.av_packet_alloc() orelse return error.OutOfMemory,
    };
}

pub fn deinit(self: *@This()) void {
    var packet: ?*c.AVPacket = self.packet;
    c.av_packet_free(&packet);

    var format_ctx: ?*c.AVFormatContext = self.format_ctx;
    c.avformat_close_input(&format_ctx);
}

pub fn streamCount(self: *const @This()) u32 {
    return self.format_ctx.nb_streams;
}

pub fn streamInfo(self: *const @This(), index: u32) !StreamInfo {
    if (index >= self.format_ctx.nb_streams) return error.StreamNotFound;

    const stream = self.format_ctx.streams[index];
    const codecpar = stream.*.codecpar;

    return .{
        .index = index,
        .kind = streamKind(codecpar.*.codec_type),
        .codec = codec(codecpar.*.codec_id),
        .time_base = .{
            .num = stream.*.time_base.num,
            .den = stream.*.time_base.den,
        },
    };
}

pub fn firstSupportedVideoStream(self: *const @This()) !?StreamInfo {
    var index: u32 = 0;
    while (index < self.streamCount()) : (index += 1) {
        const stream = try self.streamInfo(index);
        if (stream.kind == .video and isSupportedVideoCodec(stream.codec)) {
            return stream;
        }
    }
    return null;
}

/// Returned packet data is borrowed from this demuxer until the next
/// `readPacketForStream` call or `deinit`.
fn readPacket(self: *@This()) !?Packet {
    c.av_packet_unref(self.packet);

    const result = c.av_read_frame(self.format_ctx, self.packet);
    if (result == c.AVERROR_EOF) return null;
    if (result < 0) return error.Ffmpeg;

    return .{
        .data = self.packet.data[0..@intCast(self.packet.size)],
        .stream_index = @intCast(self.packet.stream_index),
        .pts = timestamp(self.packet.pts),
        .dts = timestamp(self.packet.dts),
    };
}

pub fn readPacketForStream(self: *@This(), stream_index: u32) !?Packet {
    while (try self.readPacket()) |packet| {
        if (packet.stream_index == stream_index) {
            return packet;
        }
    }
    return null;
}

fn timestamp(value: i64) ?i64 {
    return if (value == c.AV_NOPTS_VALUE) null else value;
}

fn streamKind(media_type: c.enum_AVMediaType) StreamInfo.Kind {
    return switch (media_type) {
        c.AVMEDIA_TYPE_VIDEO => .video,
        c.AVMEDIA_TYPE_AUDIO => .audio,
        c.AVMEDIA_TYPE_SUBTITLE => .subtitle,
        else => .other,
    };
}

fn codec(codec_id: c_uint) StreamInfo.Codec {
    return switch (codec_id) {
        c.AV_CODEC_ID_H264 => .h264,
        c.AV_CODEC_ID_HEVC => .hevc,
        c.AV_CODEC_ID_AV1 => .av1,
        c.AV_CODEC_ID_VP9 => .vp9,
        c.AV_CODEC_ID_AAC => .aac,
        c.AV_CODEC_ID_OPUS => .opus,
        c.AV_CODEC_ID_MP3 => .mp3,
        else => .unknown,
    };
}

fn isSupportedVideoCodec(codec_id: StreamInfo.Codec) bool {
    return switch (codec_id) {
        .h264, .hevc, .av1, .vp9 => true,
        else => false,
    };
}
