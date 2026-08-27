const std = @import("std");

const Packet = @import("../ffmpeg/Packet.zig");

buffer: []Packet,
read_index: usize = 0,
len: usize = 0,
closed: bool = false,
lock: std.atomic.Mutex = .unlocked,

pub fn init(allocator: std.mem.Allocator, capacity: usize) !@This() {
    if (capacity == 0) return error.InvalidCapacity;

    return .{
        .buffer = try allocator.alloc(Packet, capacity),
    };
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    while (self.popReady()) |packet| {
        var owned = packet;
        owned.deinit();
    }
    allocator.free(self.buffer);
    self.* = undefined;
}

pub fn push(self: *@This(), packet: Packet) !void {
    var owned = packet;
    while (true) {
        self.lockQueue();
        if (self.closed) {
            self.lock.unlock();
            owned.deinit();
            return error.QueueClosed;
        }

        if (self.len < self.buffer.len) {
            const write_index = (self.read_index + self.len) % self.buffer.len;
            self.buffer[write_index] = owned;
            self.len += 1;
            self.lock.unlock();
            return;
        }
        self.lock.unlock();
        yieldThread();
    }
}

pub fn pop(self: *@This()) ?Packet {
    while (true) {
        self.lockQueue();
        if (self.popLocked()) |packet| {
            self.lock.unlock();
            return packet;
        }

        if (self.closed) {
            self.lock.unlock();
            return null;
        }

        self.lock.unlock();
        yieldThread();
    }
}

pub fn close(self: *@This()) void {
    self.lockQueue();
    self.closed = true;
    self.lock.unlock();
}

pub fn count(self: *@This()) usize {
    self.lockQueue();
    defer self.lock.unlock();
    return self.len;
}

fn popReady(self: *@This()) ?Packet {
    self.lockQueue();
    defer self.lock.unlock();
    return self.popLocked();
}

fn popLocked(self: *@This()) ?Packet {
    if (self.len == 0) return null;

    const packet = self.buffer[self.read_index];
    self.read_index = (self.read_index + 1) % self.buffer.len;
    self.len -= 1;
    return packet;
}

fn lockQueue(self: *@This()) void {
    while (!self.lock.tryLock()) {
        yieldThread();
    }
}

fn yieldThread() void {
    // ponytail: spin/yield queue wait; replace with conditions if contention shows up in profiling.
    std.Thread.yield() catch {};
}

test "push pop preserves order and close ends reads" {
    var queue = try init(std.testing.allocator, 2);
    defer queue.deinit(std.testing.allocator);

    const c = @import("../ffmpeg/bindings.zig").c;
    var first = c.av_packet_alloc() orelse return error.OutOfMemory;
    defer c.av_packet_free(&first);
    var second = c.av_packet_alloc() orelse return error.OutOfMemory;
    defer c.av_packet_free(&second);

    first.*.stream_index = 1;
    second.*.stream_index = 2;

    try queue.push(try Packet.clone(first));
    try queue.push(try Packet.clone(second));

    var first_out = queue.pop().?;
    defer first_out.deinit();
    try std.testing.expectEqual(@as(u32, 1), first_out.streamIndex());

    var second_out = queue.pop().?;
    defer second_out.deinit();
    try std.testing.expectEqual(@as(u32, 2), second_out.streamIndex());

    queue.close();
    try std.testing.expectEqual(@as(?Packet, null), queue.pop());
}
