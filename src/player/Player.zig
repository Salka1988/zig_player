const Command = @import("Command.zig").Command;
const State = @import("State.zig").State;

state: State = .idle,
path: ?[]const u8 = null,

pub fn init() @This() {
    return .{};
}

pub fn handle(self: *@This(), command: Command) void {
    switch (command) {
        .load => |path| {
            self.path = path;
            self.state = .opening;
        },
        .stop => {
            self.path = null;
            self.state = .idle;
        },
    }
}

test "player command transitions" {
    const std = @import("std");

    var player = init();
    try std.testing.expectEqual(State.idle, player.state);

    player.handle(.{ .load = "movie.mp4" });
    try std.testing.expectEqual(State.opening, player.state);
    try std.testing.expectEqualStrings("movie.mp4", player.path.?);

    player.handle(.stop);
    try std.testing.expectEqual(State.idle, player.state);
    try std.testing.expectEqual(@as(?[]const u8, null), player.path);
}
