pub const Player = @import("player/Player.zig");
pub const State = @import("player/State.zig").State;
pub const Command = @import("player/Command.zig").Command;
pub const VideoProbe = @import("player/VideoProbe.zig");
pub const Codec = @import("domain/Codec.zig").Codec;
pub const Packet = @import("domain/Packet.zig");
pub const StreamInfo = @import("domain/StreamInfo.zig");
pub const TimeBase = @import("domain/TimeBase.zig");
pub const Timestamp = @import("domain/Timestamp.zig");
pub const AudioFrame = @import("domain/AudioFrame.zig");
pub const VideoFrame = @import("domain/VideoFrame.zig");
pub const FfmpegDemuxer = @import("demux/FfmpegDemuxer.zig");
pub const FfmpegAudioDecoder = @import("codec/audio/FfmpegAudioDecoder.zig");
pub const FfmpegVideoDecoder = @import("codec/video/FfmpegVideoDecoder.zig");
pub const ffmpeg = @import("ffmpeg/bindings.zig");

test {
    _ = @import("player/Player.zig");
    _ = @import("player/VideoProbe.zig");
    _ = @import("demux/FfmpegDemuxer.zig");
    _ = @import("codec/audio/FfmpegAudioDecoder.zig");
    _ = @import("codec/video/FfmpegVideoDecoder.zig");
    _ = @import("ffmpeg/bindings.zig");
}
