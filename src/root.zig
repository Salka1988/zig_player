pub const Player = @import("player/Player.zig");
pub const State = @import("player/State.zig").State;
pub const Command = @import("player/Command.zig").Command;
pub const Packet = @import("domain/Packet.zig");

test {
    _ = @import("player/Player.zig");
}
