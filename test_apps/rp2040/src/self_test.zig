const std = @import("std");

pub const Instance = struct {
    name: []const u8,
    execute: fn () Result,
};

pub const Failure = struct {
    msg: ?[]const u8,
    context: std.builtin.SourceLocation,

    pub fn log(self: Failure, logger: anytype) void {
        logger.err("Test failure encountered at: {s}:{s}:{d}", .{ self.context.file, self.context.fn_name, self.context.line });
        if (self.msg) |m| {
            logger.err("    {s}", .{m});
        }
    }
};

pub const Result = union(enum) {
    pass,
    fail: Failure,
};
