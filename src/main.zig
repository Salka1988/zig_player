const std = @import("std");

const zig_player = @import("zig_player");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer _ = debug_allocator.deinit();

    var player = zig_player.Player.init(debug_allocator.allocator());
    defer player.deinit();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len > 1) {
        try player.handle(.{ .load = args[1] });
    }

    std.debug.print("state: {s}\n", .{@tagName(player.state)});
}
