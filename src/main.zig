const std = @import("std");
const builtin = @import("builtin");

const zig_player = @import("zig_player");

pub fn main(init: std.process.Init) !void {
    if (builtin.mode == .Debug) {
        var debug_allocator = std.heap.DebugAllocator(.{}){};
        defer std.debug.assert(debug_allocator.deinit() == .ok);
        try run(init, debug_allocator.allocator());
    } else {
        try run(init, std.heap.smp_allocator);
    }
}

fn run(init: std.process.Init, player_allocator: std.mem.Allocator) !void {
    const PacketSummary = struct {
        stream_index: u32,
        bytes: usize,
        pts: ?i64,
        dts: ?i64,
    };

    const arena: std.mem.Allocator = init.arena.allocator();

    var player = zig_player.Player.init(player_allocator);
    defer player.deinit();

    const args = try init.minimal.args.toSlice(arena);
    var packet_summary: ?PacketSummary = null;
    if (args.len > 1) {
        try std.Io.Dir.cwd().access(init.io, args[1], .{});
        try player.handle(.{ .load = args[1] });

        var demuxer = try zig_player.FfmpegDemuxer.open(player_allocator, args[1]);
        defer demuxer.deinit();

        var stream_index: u32 = 0;
        while (stream_index < demuxer.streamCount()) : (stream_index += 1) {
            const stream = try demuxer.streamInfo(stream_index);
            std.debug.print(
                "stream: index={d} kind={s} codec={s}\n",
                .{ stream.index, @tagName(stream.kind), @tagName(stream.codec) },
            );
        }

        if (try demuxer.firstSupportedVideoStream()) |stream| {
            std.debug.print(
                "video: stream={d} codec={s}\n",
                .{ stream.index, @tagName(stream.codec) },
            );
        }

        if (try demuxer.readPacket()) |p| {
            packet_summary = .{
                .stream_index = p.stream_index,
                .bytes = p.data.len,
                .pts = p.pts,
                .dts = p.dts,
            };
        }
    }

    std.debug.print("state: {s}\n", .{@tagName(player.state)});
    if (packet_summary) |p| {
        std.debug.print(
            "packet: stream={d} bytes={d} pts={?d} dts={?d}\n",
            .{ p.stream_index, p.bytes, p.pts, p.dts },
        );
    }
}
