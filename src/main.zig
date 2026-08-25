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
    var audio_frame: ?zig_player.AudioFrame = null;
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

        const result = try zig_player.VideoProbe.decodeFirstFrames(player_allocator, args[1], &frames);
        frame_count = result.frame_count;

        if (result.video_stream) |stream| {
            std.debug.print(
                "video: stream={d} codec={s}\n",
                .{ stream.index, @tagName(stream.codec) },
            );
        }

        if (try demuxer.firstSupportedAudioStream()) |stream| {
            std.debug.print(
                "audio: stream={d} codec={s}\n",
                .{ stream.index, @tagName(stream.codec) },
            );

            var decoder = try zig_player.FfmpegAudioDecoder.openFromDemuxer(&demuxer, stream);
            defer decoder.deinit();

            while (audio_frame == null) {
                if (try demuxer.readPacketForStream(stream.index)) |_| {
                    try decoder.sendCurrentPacket(&demuxer);
                    audio_frame = try decoder.receive();
                } else {
                    try decoder.sendEndOfStream();
                    audio_frame = try decoder.receive();
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
    if (audio_frame) |frame| {
        std.debug.print(
            "audio frame: samples={d} rate={d} channels={d} time={?d:.3}s\n",
            .{ frame.sample_count, frame.sample_rate, frame.channel_count, if (frame.pts) |pts| pts.seconds else null },
        );
    }
}
