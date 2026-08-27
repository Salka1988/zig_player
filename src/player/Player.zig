const std = @import("std");

const MediaProbe = @import("MediaProbe.zig");
const State = @import("State.zig").State;
const VideoProbe = @import("VideoProbe.zig");

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

fn clearPath(self: *@This()) void {
    if (self.path) |path| {
        self.allocator.free(path);
        self.path = null;
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
