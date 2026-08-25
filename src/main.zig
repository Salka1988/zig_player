const std = @import("std");
const builtin = @import("builtin");

const zig_player = @import("zig_player");

pub fn main(init: std.process.Init) !void {
    if (builtin.mode == .Debug) {
        var debug_allocator = std.heap.DebugAllocator(.{}){};
        defer _ = debug_allocator.deinit();
        try run(init, debug_allocator.allocator());
    } else {
        try run(init, std.heap.smp_allocator);
    }
}

fn run(init: std.process.Init, player_allocator: std.mem.Allocator) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    var player = zig_player.Player.init(player_allocator);
    defer player.deinit();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len > 1) {
        try player.handle(.{ .load = args[1] });
    }

    std.debug.print("state: {s}\n", .{@tagName(player.state)});
}
