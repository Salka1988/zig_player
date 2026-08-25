const std = @import("std");

const Packet = @import("../domain/Packet.zig");
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
    errdefer c.avformat_close_input(&format_ctx);

    if (c.avformat_find_stream_info(format_ctx, null) < 0) {
        return error.Ffmpeg;
    }

    const packet = c.av_packet_alloc() orelse return error.OutOfMemory;

    return .{
        .format_ctx = format_ctx.?,
        .packet = packet,
    };
}

pub fn deinit(self: *@This()) void {
    var packet: ?*c.AVPacket = self.packet;
    c.av_packet_free(&packet);

    var format_ctx: ?*c.AVFormatContext = self.format_ctx;
    c.avformat_close_input(&format_ctx);
}

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
