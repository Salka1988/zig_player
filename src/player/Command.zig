pub const Command = union(enum) {
    load: []const u8,
    stop,
};
