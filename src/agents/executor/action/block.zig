//! Action block contract — Executor Agent · ACT phase (no LLM).

const std = @import("std");
const types = @import("../../../types.zig");

pub const Block = struct {
    id: []const u8,
    kind: types.ActionKind,

    ptr: *anyopaque,
    runFn: *const fn (
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        io: std.Io,
        action: types.Action,
    ) types.ExecutorError!types.ActionResult,

    /// Run one Executor action through the kind-specific runFn vtable.
    pub fn run(
        self: Block,
        allocator: std.mem.Allocator,
        io: std.Io,
        action: types.Action,
    ) types.ExecutorError!types.ActionResult {
        return self.runFn(self.ptr, allocator, io, action);
    }
};

/// Map ActionKind to concrete action block; verify handled by Monitor only.
pub fn blockForKind(kind: types.ActionKind) ?Block {
    return switch (kind) {
        .shell => shell_runner.block(),
        .file_edit => file_editor.block(),
        .git => git_ops.block(),
        .verify => null, // Monitor-only in skeleton
        .mcp => mcp_bridge.block(),
        .skill => skill_runner.block(),
    };
}

pub const shell_runner = @import("shell_runner.zig");
pub const file_editor = @import("file_editor.zig");
pub const git_ops = @import("git_ops.zig");
pub const mcp_bridge = @import("mcp_bridge.zig");
pub const skill_runner = @import("skill_runner.zig");
pub const stream_sink = @import("stream_sink.zig");
