const std = @import("std");

const Command = @import("Command.zig").Command;
const State = @import("State.zig").State;

allocator: std.mem.Allocator,
state: State = .idle,
path: ?[]const u8 = null,

pub fn init(allocator: std.mem.Allocator) @This() {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *@This()) void {
    self.clearPath();
}

pub fn handle(self: *@This(), command: Command) !void {
    switch (command) {
        .load => |path| {
            self.clearPath();
            self.path = try self.allocator.dupe(u8, path);
            self.state = .opening;
        },
        .stop => {
            self.clearPath();
            self.state = .idle;
        },
    }
}

fn clearPath(self: *@This()) void {
    if (self.path) |path| {
        self.allocator.free(path);
        self.path = null;
    }
}

test "player command transitions" {
    var player = init(std.testing.allocator);
    defer player.deinit();
    try std.testing.expectEqual(State.idle, player.state);

    try player.handle(.{ .load = "movie.mp4" });
    try std.testing.expectEqual(State.opening, player.state);
    try std.testing.expectEqualStrings("movie.mp4", player.path.?);

    try player.handle(.stop);
    try std.testing.expectEqual(State.idle, player.state);
    try std.testing.expectEqual(@as(?[]const u8, null), player.path);
}

test "load replaces owned path" {
    var player = init(std.testing.allocator);
    defer player.deinit();

    try player.handle(.{ .load = "first.mp4" });
    try player.handle(.{ .load = "second.mp4" });

    try std.testing.expectEqual(State.opening, player.state);
    try std.testing.expectEqualStrings("second.mp4", player.path.?);
}
