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
        .codec_id = @intCast(codecpar.*.codec_id),
    };
}

/// Returned packet data is borrowed from this demuxer until the next
/// `readPacket` call or `deinit`.
pub fn readPacket(self: *@This()) !?Packet {
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
