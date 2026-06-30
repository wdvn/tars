const std = @import("std");
const types = @import("../../../types.zig");
const llm = @import("../../../llm/mod.zig");
const rb = @import("block.zig");
const invoke_llm = @import("invoke_llm.zig");

const output_schema =
    \\{"type":"object","properties":{"risk":{"type":"string"},"level":{"type":"string","enum":["high","medium","low"]},"mitigation":{"type":"string"},"alternative":{"type":"string"}},"required":["risk","level","mitigation","alternative"]}
;

const system_prompt =
    \\You are the TARS Risk Assessor (Analyst Agent). State realistic probability and blast radius.
    \\Do not sugarcoat. Include mitigation and plan B. Output strict JSON only.
;

/// Register ASSESS-phase risk block (blast radius, mitigation, plan B).
pub fn block() rb.Block {
    return .{
        .id = "risk_assessor",
        .phase = .assess,
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
    return invoke_llm.completeJson(allocator, provider, ctx, system_prompt, output_schema, "risk_report", 0.1);
}

var state: u8 = 0;
