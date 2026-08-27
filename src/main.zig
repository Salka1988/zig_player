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
    const arena: std.mem.Allocator = init.arena.allocator();

    var player = zig_player.Player.init(player_allocator);
    defer player.deinit();

    const args = try init.minimal.args.toSlice(arena);
    var frames: [0]zig_player.VideoProbe.FrameSummary = .{};
    var probe: ?zig_player.MediaProbe.Result = null;
    var video_play_stats: zig_player.Player.VideoDecodeStats = .{};
    defer if (probe) |*result| result.deinit(player_allocator);

    if (args.len > 1) {
        try std.Io.Dir.cwd().access(init.io, args[1], .{});
        try player.open(args[1]);

        probe = try player.probeLoaded(&frames);
        video_play_stats = try player.playLoadedVideoWindow();

        for (probe.?.streams) |stream| {
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

        if (probe.?.video.video_stream) |stream| {
            std.debug.print(
                "video: stream={d} codec={s}\n",
                .{ stream.index, @tagName(stream.codec) },
            );
        }

        if (probe.?.audio.audio_stream) |stream| {
            std.debug.print(
                "audio: stream={d} codec={s}\n",
                .{ stream.index, @tagName(stream.codec) },
            );
        }
    }

    std.debug.print("state: {s}\n", .{@tagName(player.state)});
    if (probe) |result| if (result.audio.frame) |frame| {
        std.debug.print(
            "audio frame: samples={d} rate={d} channels={d} time={?d:.3}s\n",
            .{ frame.sample_count, frame.sample_rate, frame.channel_count, if (frame.pts) |pts| pts.seconds else null },
        );
    };
    if (video_play_stats.frame_count > 0) {
        std.debug.print(
            "video window: frames={d} dropped={d} last_time={?d:.3}s\n",
            .{ video_play_stats.frame_count, video_play_stats.dropped_frame_count, video_play_stats.last_time_seconds },
        );
    }
}
