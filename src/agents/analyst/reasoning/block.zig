//! Reasoning block contract — LLM lives here (Analyst Agent).

const std = @import("std");
const types = @import("../../../types.zig");
const llm = @import("../../../llm/mod.zig");

pub const Block = struct {
    id: []const u8,
    phase: types.Phase,

    ptr: *anyopaque,
    invokeFn: *const fn (
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        provider: llm.Provider,
        ctx: *const types.MissionContext,
    ) types.BlockError!types.BlockResult,

    pub fn invoke(
        self: Block,
        allocator: std.mem.Allocator,
        provider: llm.Provider,
        ctx: *const types.MissionContext,
    ) types.BlockError!types.BlockResult {
        return self.invokeFn(self.ptr, allocator, provider, ctx);
    }
};

pub fn assemblePrompt(
    allocator: std.mem.Allocator,
    template: []const u8,
    ctx: *const types.MissionContext,
    output_schema: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        \\{s}
        \\
        \\Mission: {s}
        \\Goal: {s}
        \\Phase: {s}
        \\Evidence:
        \\{s}
        \\Respond ONLY with JSON matching:
        \\{s}
    , .{
        template,
        ctx.mission_id,
        ctx.goal,
        ctx.phase.name(),
        ctx.evidence,
        output_schema,
    });
}
