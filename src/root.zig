pub const Player = @import("player/Player.zig");
pub const State = @import("player/State.zig").State;
pub const Command = @import("player/Command.zig").Command;
pub const Codec = @import("domain/Codec.zig").Codec;
pub const Packet = @import("domain/Packet.zig");
pub const StreamInfo = @import("domain/StreamInfo.zig");
pub const FfmpegDemuxer = @import("demux/FfmpegDemuxer.zig");
pub const ffmpeg = @import("ffmpeg/bindings.zig");

test {
    _ = @import("player/Player.zig");
    _ = @import("demux/FfmpegDemuxer.zig");
    _ = @import("ffmpeg/bindings.zig");
}
