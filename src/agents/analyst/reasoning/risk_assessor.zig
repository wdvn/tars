const std = @import("std");
const types = @import("../../../types.zig");
const llm = @import("../../../llm/mod.zig");
const rb = @import("block.zig");

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

/// Call LLM with risk schema; very low temperature for conservative estimates.
fn invoke(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    provider: llm.Provider,
    ctx: *const types.MissionContext,
) types.BlockError!types.BlockResult {
    _ = ptr;
    const prompt = rb.assemblePrompt(allocator, system_prompt, ctx, output_schema) catch return types.BlockError.InvalidInput;
    defer allocator.free(prompt);

    const response = provider.complete(allocator, .{
        .config = .{ .temperature = 0.1 },
        .system = system_prompt,
        .messages = &.{
            .{ .role = "user", .content = prompt },
        },
        .output_schema = output_schema,
    }) catch return types.BlockError.LlmFailed;
    defer allocator.free(response.content_json);

    const payload = allocator.dupe(u8, response.content_json) catch return types.BlockError.InvalidInput;
    return .{ .kind = "risk_report", .payload_json = payload };
}

var state: u8 = 0;
