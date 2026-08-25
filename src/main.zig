const std = @import("std");
const Io = std.Io;

const zig_player = @import("zig_player");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    var player = zig_player.Player.init(arena);
    defer player.deinit();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len > 1) {
        try player.handle(.{ .load = args[1] });
    }

    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stdout_writer.print("state: {s}\n", .{@tagName(player.state)});
    try stdout_writer.flush();
}
