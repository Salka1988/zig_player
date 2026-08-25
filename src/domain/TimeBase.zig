num: i32,
den: i32,

pub fn seconds(self: @This(), timestamp: i64) f64 {
    return @as(f64, @floatFromInt(timestamp)) *
        @as(f64, @floatFromInt(self.num)) /
        @as(f64, @floatFromInt(self.den));
}
