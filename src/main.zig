const std = @import("std");
const builtin = @import("builtin");

const zig_player = @import("zig_player");

pub fn main(init: std.process.Init) !void {
    if (builtin.mode == .Debug) {
        var debug_allocator = std.heap.DebugAllocator(.{}){};
        defer _ = debug_allocator.deinit();
        try run(init, debug_allocator.allocator());
    } else {
        try run(init, std.heap.smp_allocator);
    }
}

fn run(init: std.process.Init, player_allocator: std.mem.Allocator) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    var player = zig_player.Player.init(player_allocator);
    defer player.deinit();

    const args = try init.minimal.args.toSlice(arena);
    var packet: ?zig_player.Packet = null;
    if (args.len > 1) {
        try std.Io.Dir.cwd().access(init.io, args[1], .{});
        try player.handle(.{ .load = args[1] });

        var demuxer = try zig_player.FfmpegDemuxer.open(player_allocator, args[1]);
        defer demuxer.deinit();
        packet = try demuxer.readPacket();
    }

    std.debug.print("state: {s}\n", .{@tagName(player.state)});
    if (packet) |p| {
        std.debug.print(
            "packet: stream={d} bytes={d} pts={?d} dts={?d}\n",
            .{ p.stream_index, p.data.len, p.pts, p.dts },
        );
    }
}
