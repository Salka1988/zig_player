const std = @import("std");

const FfmpegAudioDecoder = @import("../codec/audio/FfmpegAudioDecoder.zig");
const FfmpegDemuxer = @import("../demux/FfmpegDemuxer.zig");
const FfmpegVideoDecoder = @import("../codec/video/FfmpegVideoDecoder.zig");
const MediaProbe = @import("MediaProbe.zig");
const State = @import("State.zig").State;
const VideoProbe = @import("VideoProbe.zig");

pub const VideoDecodeStats = struct {
    frame_count: usize = 0,
    last_time_seconds: ?f64 = null,
};

pub const AudioDecodeStats = struct {
    frame_count: usize = 0,
    sample_count: usize = 0,
    last_time_seconds: ?f64 = null,
};

pub const MediaDecodeStats = struct {
    video: VideoDecodeStats = .{},
    audio: AudioDecodeStats = .{},
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

pub fn decodeLoadedMedia(self: *@This()) !MediaDecodeStats {
    var demuxer = try FfmpegDemuxer.open(self.allocator, self.path orelse return error.NoMediaLoaded);
    defer demuxer.deinit();

    const video_stream = try demuxer.firstSupportedVideoStream();
    const audio_stream = try demuxer.firstSupportedAudioStream();

    var video_decoder: ?FfmpegVideoDecoder = if (video_stream) |stream|
        try FfmpegVideoDecoder.openFromDemuxer(&demuxer, stream)
    else
        null;
    defer if (video_decoder) |*decoder| decoder.deinit();

    var audio_decoder: ?FfmpegAudioDecoder = if (audio_stream) |stream|
        try FfmpegAudioDecoder.openFromDemuxer(&demuxer, stream)
    else
        null;
    defer if (audio_decoder) |*decoder| decoder.deinit();

    var stats: MediaDecodeStats = .{};
    while (try demuxer.readPacket()) |stream_index| {
        if (video_stream != null and stream_index == video_stream.?.index) {
            try video_decoder.?.sendCurrentPacket(&demuxer);
            try receiveVideoStats(&video_decoder.?, &stats.video);
        } else if (audio_stream != null and stream_index == audio_stream.?.index) {
            try audio_decoder.?.sendCurrentPacket(&demuxer);
            try receiveAudioStats(&audio_decoder.?, &stats.audio);
        }
    }

    if (video_decoder) |*decoder| {
        try decoder.sendEndOfStream();
        try receiveVideoStats(decoder, &stats.video);
    }
    if (audio_decoder) |*decoder| {
        try decoder.sendEndOfStream();
        try receiveAudioStats(decoder, &stats.audio);
    }

    return stats;
}

fn clearPath(self: *@This()) void {
    if (self.path) |path| {
        self.allocator.free(path);
        self.path = null;
    }
}

fn receiveVideoStats(decoder: *FfmpegVideoDecoder, stats: *VideoDecodeStats) !void {
    while (try decoder.receive()) |frame| {
        stats.frame_count += 1;
        stats.last_time_seconds = if (frame.pts) |pts| pts.seconds else null;
    }
}

fn receiveAudioStats(decoder: *FfmpegAudioDecoder, stats: *AudioDecodeStats) !void {
    while (try decoder.receive()) |frame| {
        stats.frame_count += 1;
        stats.sample_count += frame.sample_count;
        stats.last_time_seconds = if (frame.pts) |pts| pts.seconds else null;
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
