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
    const max_frames = 5;
    const FrameSummary = struct {
        width: u32,
        height: u32,
        time_seconds: ?f64,
    };

    const arena: std.mem.Allocator = init.arena.allocator();

    var player = zig_player.Player.init(player_allocator);
    defer player.deinit();

    const args = try init.minimal.args.toSlice(arena);
    var frames: [max_frames]FrameSummary = undefined;
    var frame_count: usize = 0;
    if (args.len > 1) {
        try std.Io.Dir.cwd().access(init.io, args[1], .{});
        try player.handle(.{ .load = args[1] });

        var demuxer = try zig_player.FfmpegDemuxer.open(player_allocator, args[1]);
        defer demuxer.deinit();

        var stream_index: u32 = 0;
        while (stream_index < demuxer.streamCount()) : (stream_index += 1) {
            const stream = try demuxer.streamInfo(stream_index);
            std.debug.print(
                "stream: index={d} kind={s} codec={s} time_base={d}/{d}\n",
                .{
                    stream.index,
                    @tagName(stream.kind),
                    @tagName(stream.codec),
                    stream.time_base.num,
                    stream.time_base.den,
                },
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

            while (frame_count < max_frames) {
                if (try demuxer.readPacketForStream(stream.index)) |_| {
                    try decoder.sendCurrentPacket(&demuxer);
                    while (frame_count < max_frames) {
                        const frame = (try decoder.receive()) orelse break;
                        frames[frame_count] = .{
                            .width = frame.width,
                            .height = frame.height,
                            .time_seconds = if (frame.pts) |pts| pts.seconds else null,
                        };
                        frame_count += 1;
                    }
                } else {
                    try decoder.sendEndOfStream();
                    while (frame_count < max_frames) {
                        const frame = (try decoder.receive()) orelse break;
                        frames[frame_count] = .{
                            .width = frame.width,
                            .height = frame.height,
                            .time_seconds = if (frame.pts) |pts| pts.seconds else null,
                        };
                        frame_count += 1;
                    }
                    break;
                }
            }
        }
    }

    std.debug.print("state: {s}\n", .{@tagName(player.state)});
    for (frames[0..frame_count]) |frame| {
        std.debug.print(
            "frame: {d}x{d} time={?d:.3}s\n",
            .{ frame.width, frame.height, frame.time_seconds },
        );
    }
}
