const std = @import("std");
const types = @import("../../../types.zig");
const llm = @import("../../../llm/mod.zig");
const rb = @import("block.zig");
const invoke_llm = @import("invoke_llm.zig");

const output_schema =
    \\{"type":"object","properties":{"options":{"type":"array","items":{"type":"object","properties":{"name":{"type":"string"},"cost":{"type":"array","items":{"type":"string"}},"benefit":{"type":"array","items":{"type":"string"}}},"required":["name","cost","benefit"]}}},"required":["options"]}
;

const system_prompt =
    \\You are the TARS Trade-off Resolver (Analyst Agent). When constraints conflict, rank options.
    \\Encode necessary sacrifice (hotfix vs deep fix, scope vs deadline). Output strict JSON only.
;

/// Register PLAN-phase trade-off block (rank conflicting options).
pub fn block() rb.Block {
    return .{
        .id = "trade_off",
        .phase = .plan,
        .ptr = @ptrCast(@constCast(&state)),
        .invokeFn = invoke,
    };
}

fn invoke(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    provider: llm.Provider,
    ctx: *const types.MissionContext,
) types.BlockError!types.BlockResult {
    _ = ptr;
    return invoke_llm.completeJson(allocator, provider, ctx, system_prompt, output_schema, "trade_off", 0.15);
}

var state: u8 = 0;
