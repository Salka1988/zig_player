const std = @import("std");

const FfmpegDemuxer = @import("../demux/FfmpegDemuxer.zig");
const FfmpegAudioDecoder = @import("../codec/audio/FfmpegAudioDecoder.zig");
const FfmpegVideoDecoder = @import("../codec/video/FfmpegVideoDecoder.zig");
const MediaProbe = @import("MediaProbe.zig");
const SdlAudioOutput = @import("../audio/sdl/SdlAudioOutput.zig");
const SdlVideoOutput = @import("../video/sdl/SdlVideoOutput.zig");
const State = @import("State.zig").State;
const VideoProbe = @import("VideoProbe.zig");
const sdl = @import("../sdl/bindings.zig");

pub const VideoDecodeStats = struct {
    frame_count: usize = 0,
    last_time_seconds: ?f64 = null,
};

const VideoPlaybackClock = struct {
    start_ms: ?u64 = null,
    first_frame_seconds: ?f64 = null,
};

allocator: std.mem.Allocator,
state: State = .idle,
path: ?[]const u8 = null,

pub fn init(allocator: std.mem.Allocator) @This() {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *@This()) void {
    self.clearPath();
}

pub fn open(self: *@This(), path: []const u8) !void {
    self.clearPath();
    self.path = try self.allocator.dupe(u8, path);
    self.state = .opening;
}

pub fn stop(self: *@This()) void {
    self.clearPath();
    self.state = .idle;
}

pub fn probeLoaded(
    self: *@This(),
    video_frames: []VideoProbe.FrameSummary,
) !MediaProbe.Result {
    return MediaProbe.run(self.allocator, self.path orelse return error.NoMediaLoaded, video_frames);
}

pub fn playLoadedVideoWindow(self: *@This()) !VideoDecodeStats {
    var demuxer = try FfmpegDemuxer.open(self.allocator, self.path orelse return error.NoMediaLoaded);
    defer demuxer.deinit();

    const video_stream = (try demuxer.firstSupportedVideoStream()) orelse return .{};
    const audio_stream = try demuxer.firstSupportedAudioStream();

    var video_decoder = try FfmpegVideoDecoder.openFromDemuxer(&demuxer, video_stream);
    defer video_decoder.deinit();

    var audio_decoder: ?FfmpegAudioDecoder = if (audio_stream) |stream|
        try FfmpegAudioDecoder.openFromDemuxer(&demuxer, stream)
    else
        null;
    defer if (audio_decoder) |*decoder| decoder.deinit();

    var video_output: ?SdlVideoOutput = null;
    defer if (video_output) |*output| output.deinit();

    var audio_output: ?SdlAudioOutput = null;
    defer if (audio_output) |*output| output.deinit();

    var clock: VideoPlaybackClock = .{};
    var stats: VideoDecodeStats = .{};
    while (try demuxer.readPacket()) |stream_index| {
        if (stream_index == video_stream.index) {
            try video_decoder.sendCurrentPacket(&demuxer);
            if (!try receiveAndPresentVideo(&video_decoder, &video_output, &audio_output, &clock, &stats)) return stats;
        } else if (audio_stream != null and stream_index == audio_stream.?.index) {
            try audio_decoder.?.sendCurrentPacket(&demuxer);
            try receiveAndQueueAudio(&audio_decoder.?, &audio_output, self.allocator);
        }
    }

    try video_decoder.sendEndOfStream();
    _ = try receiveAndPresentVideo(&video_decoder, &video_output, &audio_output, &clock, &stats);

    if (audio_decoder) |*decoder| {
        try decoder.sendEndOfStream();
        try receiveAndQueueAudio(decoder, &audio_output, self.allocator);
    }

    if (audio_output) |*output| output.drain();

    return stats;
}

fn clearPath(self: *@This()) void {
    if (self.path) |path| {
        self.allocator.free(path);
        self.path = null;
    }
}

fn receiveAndPresentVideo(
    decoder: *FfmpegVideoDecoder,
    output: *?SdlVideoOutput,
    audio_output: *?SdlAudioOutput,
    clock: *VideoPlaybackClock,
    stats: *VideoDecodeStats,
) !bool {
    while (try decoder.receive()) |frame| {
        stats.frame_count += 1;
        stats.last_time_seconds = if (frame.pts) |pts| pts.seconds else null;

        if (output.* == null) {
            output.* = try SdlVideoOutput.init(frame.width, frame.height);
        }

        waitForVideoTime(clock, audio_output, stats.last_time_seconds);
        if (!try output.*.?.present(try decoder.currentYuv420p())) {
            return false;
        }
    }
    return true;
}

fn receiveAndQueueAudio(
    decoder: *FfmpegAudioDecoder,
    output: *?SdlAudioOutput,
    allocator: std.mem.Allocator,
) !void {
    while (try decoder.receive()) |_| {
        const frame = try decoder.currentF32Planar();
        if (output.* == null) {
            output.* = try SdlAudioOutput.init(frame.sample_rate, frame.channel_count);
        }
        try output.*.?.queueF32Planar(allocator, frame);
    }
}

fn waitForVideoTime(
    clock: *VideoPlaybackClock,
    audio_output: *?SdlAudioOutput,
    frame_seconds: ?f64,
) void {
    const seconds = frame_seconds orelse return;

    if (audio_output.*) |*output| {
        if (output.waitUntil(seconds)) return;
    }

    if (clock.first_frame_seconds == null) {
        clock.first_frame_seconds = seconds;
        clock.start_ms = sdl.SDL_GetTicks64();
        return;
    }

    const elapsed_seconds = seconds - clock.first_frame_seconds.?;
    if (elapsed_seconds <= 0) return;

    const target_ms = clock.start_ms.? + @as(u64, @intFromFloat(elapsed_seconds * std.time.ms_per_s));
    const now_ms = sdl.SDL_GetTicks64();
    if (target_ms > now_ms) {
        sdl.SDL_Delay(@intCast(target_ms - now_ms));
    }
}

test "load owns path and stop clears it" {
    var player = init(std.testing.allocator);
    defer player.deinit();

    try player.open("first.mp4");
    try std.testing.expectEqual(State.opening, player.state);
    try std.testing.expectEqualStrings("first.mp4", player.path.?);

    try player.open("second.mp4");
    try std.testing.expectEqual(State.opening, player.state);
    try std.testing.expectEqualStrings("second.mp4", player.path.?);

    player.stop();
    try std.testing.expectEqual(State.idle, player.state);
    try std.testing.expectEqual(@as(?[]const u8, null), player.path);
}
