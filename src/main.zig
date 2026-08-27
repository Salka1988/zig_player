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

    const arena: std.mem.Allocator = init.arena.allocator();

    var player = zig_player.Player.init(player_allocator);
    defer player.deinit();

    const args = try init.minimal.args.toSlice(arena);
    var frames: [max_frames]zig_player.VideoProbe.FrameSummary = undefined;
    var frame_count: usize = 0;
    var probe: ?zig_player.MediaProbe.Result = null;
    var video_decode_stats: zig_player.Player.VideoDecodeStats = .{};
    var audio_decode_stats: zig_player.Player.AudioDecodeStats = .{};
    defer if (probe) |*result| result.deinit(player_allocator);

    if (args.len > 1) {
        try std.Io.Dir.cwd().access(init.io, args[1], .{});
        try player.open(args[1]);

        probe = try player.probeLoaded(&frames);
        frame_count = probe.?.video.frame_count;
        video_decode_stats = try player.decodeLoadedVideo();
        audio_decode_stats = try player.decodeLoadedAudio();

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
    for (frames[0..frame_count]) |frame| {
        std.debug.print(
            "frame: {d}x{d} time={?d:.3}s\n",
            .{ frame.width, frame.height, frame.time_seconds },
        );
    }
    if (probe) |result| if (result.audio.frame) |frame| {
        std.debug.print(
            "audio frame: samples={d} rate={d} channels={d} time={?d:.3}s\n",
            .{ frame.sample_count, frame.sample_rate, frame.channel_count, if (frame.pts) |pts| pts.seconds else null },
        );
    };
    if (video_decode_stats.frame_count > 0) {
        std.debug.print(
            "video decoded: frames={d} last_time={?d:.3}s\n",
            .{ video_decode_stats.frame_count, video_decode_stats.last_time_seconds },
        );
    }
    if (audio_decode_stats.frame_count > 0) {
        std.debug.print(
            "audio decoded: frames={d} samples={d} last_time={?d:.3}s\n",
            .{ audio_decode_stats.frame_count, audio_decode_stats.sample_count, audio_decode_stats.last_time_seconds },
        );
    }
}
