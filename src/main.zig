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
    const FrameSummary = struct {
        width: u32,
        height: u32,
        pts: ?i64,
    };

    const arena: std.mem.Allocator = init.arena.allocator();

    var player = zig_player.Player.init(player_allocator);
    defer player.deinit();

    const args = try init.minimal.args.toSlice(arena);
    var frame_summary: ?FrameSummary = null;
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

            var decoder = try zig_player.FfmpegVideoDecoder.openFromDemuxer(&demuxer, stream);
            defer decoder.deinit();
            std.debug.print("decoder: stream={d}\n", .{decoder.stream_index});

            while (frame_summary == null) {
                if (try demuxer.readPacketForStream(stream.index)) |_| {
                    try decoder.sendCurrentPacket(&demuxer);
                    if (try decoder.receive()) |frame| {
                        frame_summary = .{
                            .width = frame.width,
                            .height = frame.height,
                            .pts = frame.pts,
                        };
                    }
                } else {
                    try decoder.sendEndOfStream();
                    if (try decoder.receive()) |frame| {
                        frame_summary = .{
                            .width = frame.width,
                            .height = frame.height,
                            .pts = frame.pts,
                        };
                    }
                    break;
                }
            }
        }
    }

    std.debug.print("state: {s}\n", .{@tagName(player.state)});
    if (frame_summary) |frame| {
        std.debug.print(
            "frame: {d}x{d} pts={?d}\n",
            .{ frame.width, frame.height, frame.pts },
        );
    }
}
