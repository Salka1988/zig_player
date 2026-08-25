const std = @import("std");
const builtin = @import("builtin");

const zig_player = @import("zig_player");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer if (builtin.mode == .Debug) {
        _ = debug_allocator.deinit();
    };

    const player_allocator = if (builtin.mode == .Debug)
        debug_allocator.allocator()
    else
        std.heap.smp_allocator;

    var player = zig_player.Player.init(player_allocator);
    defer player.deinit();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len > 1) {
        try player.handle(.{ .load = args[1] });
    }

    std.debug.print("state: {s}\n", .{@tagName(player.state)});
}
