const c = @import("bindings.zig").c;

packet: *c.AVPacket,

pub fn clone(source: *const c.AVPacket) !@This() {
    var packet = c.av_packet_alloc() orelse return error.OutOfMemory;
    errdefer c.av_packet_free(&packet);

    if (c.av_packet_ref(packet, source) < 0) return error.Ffmpeg;

    return .{ .packet = packet };
}

pub fn deinit(self: *@This()) void {
    var packet: ?*c.AVPacket = self.packet;
    c.av_packet_free(&packet);
    self.* = undefined;
}

pub fn streamIndex(self: *const @This()) u32 {
    return @intCast(self.packet.stream_index);
}
