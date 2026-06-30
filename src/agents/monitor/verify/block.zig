//! Verify block contract — Monitor Agent · VERIFY phase (read-only).

const std = @import("std");
const types = @import("../../../types.zig");

pub const MonitorError = error{
    VerifyFailed,
    StorageUnavailable,
    OutOfMemory,
};

pub const Block = struct {
    id: []const u8,

    ptr: *anyopaque,
    runFn: *const fn (
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        io: std.Io,
        command: []const u8,
    ) types.MonitorError!VerifyCheck,

    /// Execute verify command through block-specific runFn.
    pub fn run(
        self: Block,
        allocator: std.mem.Allocator,
        io: std.Io,
        command: []const u8,
    ) types.MonitorError!VerifyCheck {
        return self.runFn(self.ptr, allocator, io, command);
    }
};

pub const VerifyCheck = struct {
    name: []const u8,
    passed: bool,
    exit_code: u8,
    output: []const u8,
};

pub const verifier = @import("verifier.zig");
pub const audit_writer = @import("audit_writer.zig");
pub const handoff_builder = @import("handoff_builder.zig");
pub const health_watchdog = @import("health_watchdog.zig");

/// Default verify pipeline — shell command runner only in skeleton.
pub fn defaultBlocks() [1]Block {
    return .{verifier.block()};
}
