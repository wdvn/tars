const std = @import("std");
const types = @import("../../../types.zig");
const llm = @import("../../../llm/mod.zig");
const rb = @import("block.zig");
const invoke_llm = @import("invoke_llm.zig");

const output_schema =
    \\{"type":"object","properties":{"steps":{"type":"array","items":{"type":"string"}},"rollback":{"type":"string"},"contingencies":{"type":"array","items":{"type":"string"}}},"required":["steps","rollback","contingencies"]}
;

const system_prompt =
    \\You are the TARS Planner (Analyst Agent). Produce a minimal correct plan.
    \\Include Plan A steps, rollback path, and contingencies. Output strict JSON only.
;

/// Register PLAN-phase planner block (steps, rollback, contingencies).
pub fn block() rb.Block {
    return .{
        .id = "planner",
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
    return invoke_llm.completeJson(allocator, provider, ctx, system_prompt, output_schema, "plan", 0.2);
}

var state: u8 = 0;
