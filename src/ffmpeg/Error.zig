const std = @import("std");

pub fn check(result: c_int, operation: []const u8) !void {
    if (result >= 0) return;
    std.debug.print("ffmpeg error: {s} result={d}\n", .{ operation, result });
    return error.Ffmpeg;
}
