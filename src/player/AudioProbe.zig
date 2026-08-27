const std = @import("std");

const FfmpegAudioDecoder = @import("../codec/audio/FfmpegAudioDecoder.zig");
const FfmpegDemuxer = @import("../demux/FfmpegDemuxer.zig");
const AudioFrame = @import("../domain/AudioFrame.zig");
const StreamInfo = @import("../domain/StreamInfo.zig");

pub const Result = struct {
    audio_stream: ?StreamInfo = null,
    frame: ?AudioFrame = null,
};

pub fn decodeFirstFrame(
    allocator: std.mem.Allocator,
    path: []const u8,
) !Result {
    var demuxer = try FfmpegDemuxer.open(allocator, path);
    defer demuxer.deinit();

    const stream = (try demuxer.firstSupportedAudioStream()) orelse return .{};

    var decoder = try FfmpegAudioDecoder.openFromDemuxer(&demuxer, stream);
    defer decoder.deinit();

    while (true) {
        if (try demuxer.readPacketForStream(stream.index)) {
            try decoder.sendCurrentPacket(&demuxer);
            if (try decoder.receive()) |frame| {
                return .{ .audio_stream = stream, .frame = frame };
            }
        } else {
            try decoder.sendEndOfStream();
            return .{
                .audio_stream = stream,
                .frame = try decoder.receive(),
            };
        }
    }
}
