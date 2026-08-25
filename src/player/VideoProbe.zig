const std = @import("std");

const FfmpegDemuxer = @import("../demux/FfmpegDemuxer.zig");
const FfmpegVideoDecoder = @import("../codec/video/FfmpegVideoDecoder.zig");
const StreamInfo = @import("../domain/StreamInfo.zig");

pub const FrameSummary = struct {
    width: u32,
    height: u32,
    time_seconds: ?f64,
};

pub const Result = struct {
    video_stream: ?StreamInfo = null,
    frame_count: usize = 0,
};

pub fn decodeFirstFrames(
    allocator: std.mem.Allocator,
    path: []const u8,
    out: []FrameSummary,
) !Result {
    var demuxer = try FfmpegDemuxer.open(allocator, path);
    defer demuxer.deinit();

    const stream = (try demuxer.firstSupportedVideoStream()) orelse return .{};

    var decoder = try FfmpegVideoDecoder.openFromDemuxer(&demuxer, stream);
    defer decoder.deinit();

    var frame_count: usize = 0;
    while (frame_count < out.len) {
        if (try demuxer.readPacketForStream(stream.index)) |_| {
            try decoder.sendCurrentPacket(&demuxer);
            try receiveAvailable(&decoder, out, &frame_count);
        } else {
            try decoder.sendEndOfStream();
            try receiveAvailable(&decoder, out, &frame_count);
            break;
        }
    }

    return .{
        .video_stream = stream,
        .frame_count = frame_count,
    };
}

fn receiveAvailable(
    decoder: *FfmpegVideoDecoder,
    out: []FrameSummary,
    frame_count: *usize,
) !void {
    while (frame_count.* < out.len) {
        const frame = (try decoder.receive()) orelse break;
        out[frame_count.*] = .{
            .width = frame.width,
            .height = frame.height,
            .time_seconds = if (frame.pts) |pts| pts.seconds else null,
        };
        frame_count.* += 1;
    }
}
