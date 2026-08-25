const std = @import("std");

const AudioProbe = @import("AudioProbe.zig");
const FfmpegDemuxer = @import("../demux/FfmpegDemuxer.zig");
const StreamInfo = @import("../domain/StreamInfo.zig");
const VideoProbe = @import("VideoProbe.zig");

pub const Result = struct {
    streams: []StreamInfo,
    video: VideoProbe.Result,
    audio: AudioProbe.Result,

    pub fn deinit(self: *Result, allocator: std.mem.Allocator) void {
        allocator.free(self.streams);
        self.* = .{
            .streams = &.{},
            .video = .{},
            .audio = .{},
        };
    }
};

pub fn run(
    allocator: std.mem.Allocator,
    path: []const u8,
    video_frames: []VideoProbe.FrameSummary,
) !Result {
    var demuxer = try FfmpegDemuxer.open(allocator, path);
    defer demuxer.deinit();

    const stream_count = demuxer.streamCount();
    const streams = try allocator.alloc(StreamInfo, stream_count);
    errdefer allocator.free(streams);

    var stream_index: u32 = 0;
    while (stream_index < stream_count) : (stream_index += 1) {
        streams[stream_index] = try demuxer.streamInfo(stream_index);
    }

    return .{
        .streams = streams,
        .video = try VideoProbe.decodeFirstFrames(allocator, path, video_frames),
        .audio = try AudioProbe.decodeFirstFrame(allocator, path),
    };
}
